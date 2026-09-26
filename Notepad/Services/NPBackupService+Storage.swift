//
//  NPBackupService+Storage.swift
//  Notepad
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import CryptoKit
import Foundation

/// `NPBackupService` 的存储层：快照/元数据读写原语、会话状态落盘、缓存清理与记录读取。
///
/// 从 `NPBackupService.swift` 拆出（主文件超过 SwiftLint `file_length` / `type_body_length`
/// 阈值）。本层只做文件 IO、记录解析与元数据组装，不参与节流调度，因此
/// `backupDirectory` / `fileManager` / `writeQueue` / 文件扩展名常量 / 静态 IO 助手为
/// `internal`——它们都是 `let` 常量或无状态纯函数。
/// 元数据组装与“仅重写元数据”也在此（窗口归属/标签序变化时高频调用），
/// 因此 `Registration` 与 `registrations` 为 `internal`；
/// `lastBackupError` 的写入仍封在类内。
///
/// 主文件仍需调用的成员（`writeSessionState` / `deleteBackupFiles` /
/// `enqueueDeleteBackupFiles` / `writeBackupFiles` / `contentHash` / `makeMetadata` /
/// `enqueueMetadataWrite`）不能为 `private`（Swift 的 `private` 是文件级作用域），
/// 其余记录读取助手保持 `private`。
extension NPBackupService {

    // MARK: - 恢复

    /// 恢复崩溃前的会话。
    /// 必须包含从未保存的"无标题"文档及其光标位置（PRD FR-003）。
    /// - Returns: 可恢复的备份项列表
    func recoverableItems() -> [NPBackupItem] {
        recoverableRecords().map { record in record.item }
    }

    /// 读取全部有效备份记录（含会话归属，供启动恢复分组）。
    /// "有效"= 文件对完整、元数据可解码且未超保留期（7 天）。
    /// - Returns: 备份记录列表（按窗口组、标签序、时间戳排序）
    func recoverableRecords() -> [NPBackupRecord] {
        guard let files = try? fileManager.contentsOfDirectory(atPath: backupDirectory.path) else {
            return []
        }
        let cutoff = Date().timeIntervalSince1970 - TimeInterval(Self.retentionDays * 24 * 60 * 60)
        var records: [NPBackupRecord] = []
        for file in files where file.hasSuffix(".\(Self.metadataFileExtension)") {
            guard let record = loadRecord(metadataFileName: file),
                  record.timestamp >= cutoff else {
                continue
            }
            records.append(record)
        }

        var latestBySlot: [String: NPBackupRecord] = [:]
        for record in records {
            let key = "\(record.windowGroupID.uuidString)|\(record.tabIndex)"
            if let existing = latestBySlot[key], existing.timestamp >= record.timestamp {
                continue
            }
            latestBySlot[key] = record
        }

        return latestBySlot.values.sorted { lhs, rhs in
            if lhs.windowGroupID.uuidString != rhs.windowGroupID.uuidString {
                return lhs.windowGroupID.uuidString < rhs.windowGroupID.uuidString
            }
            if lhs.tabIndex != rhs.tabIndex {
                return lhs.tabIndex < rhs.tabIndex
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    /// 清理无效备份文件：删除目录中不属于 `validBackupIDs` 的一切文件。
    ///
    /// 覆盖四类垃圾：超期备份、原子写入临时残留（`*.sb-*` 等不匹配 `<UUID>.txt/.json` 的文件名）、
    /// 孤儿单边文件（`.json` 缺 `.txt` 或反之）、元数据损坏的记录。
    /// 典型用法：启动时以 `recoverableRecords()` 的结果为白名单调用，加载有效备份后清掉其余。
    /// - Parameter validBackupIDs: 需保留的备份标识集合
    func pruneInvalidBackupFiles(keeping validBackupIDs: Set<UUID>) {
        guard let files = try? fileManager.contentsOfDirectory(atPath: backupDirectory.path) else {
            return
        }
        for file in files {
            if file == Self.sessionStateFileName {
                continue
            }
            let name = (file as NSString).deletingPathExtension
            let ext = (file as NSString).pathExtension
            guard ext == Self.contentFileExtension || ext == Self.metadataFileExtension,
                  let backupID = UUID(uuidString: name),
                  validBackupIDs.contains(backupID) else {
                try? fileManager.removeItem(at: backupDirectory.appendingPathComponent(file))
                continue
            }
        }
    }

    // MARK: - 备份记录读取

    /// 读取备份记录（元数据与内容文件均存在才有效，且必须满足恢复所需字段合法性）。
    /// - Parameter metadataFileName: 元数据文件名
    /// - Returns: 备份记录
    private func loadRecord(metadataFileName: String) -> NPBackupRecord? {
        guard var metadata = loadMetadata(metadataFileName: metadataFileName) else {
            return nil
        }
        let backupID = backupID(fromMetadataFileName: metadataFileName)
        let contentURL = backupDirectory
            .appendingPathComponent("\(backupID.uuidString).\(Self.contentFileExtension)")
        guard fileManager.fileExists(atPath: contentURL.path),
              let windowGroupID = UUID(uuidString: metadata.windowGroupID),
              metadata.cursorPosition >= 0,
              metadata.tabIndex >= 0,
              metadata.timestamp > 0 else {
            return nil
        }
        guard let content = try? String(contentsOf: contentURL, encoding: .utf8) else {
            return nil
        }
        if let expectedHash = metadata.contentHash,
           Self.contentHash(for: content) != expectedHash {
            return nil
        }
        if let originalFilePath = metadata.originalFilePath, originalFilePath.isEmpty {
            return nil
        }
        if metadata.schemaVersion != Self.currentSchemaVersion || metadata.revision == nil
            || metadata.contentHash == nil {
            metadata.schemaVersion = Self.currentSchemaVersion
            metadata.revision = metadata.revision ?? 0
            metadata.contentHash = Self.contentHash(for: content)
            migrateMetadata(metadata, metadataFileName: metadataFileName)
        }
        let item = NPBackupItem(
            backupContentURL: contentURL,
            originalFileURL: metadata.originalFilePath.map { path in URL(fileURLWithPath: path) },
            cursorPosition: metadata.cursorPosition,
            encoding: String.Encoding(rawValue: metadata.encodingRawValue),
            lineEnding: NPLineEnding(rawValue: metadata.lineEndingRawValue) ?? .lf,
            originalFileBookmark: metadata.originalFileBookmark.flatMap { Data(base64Encoded: $0) }
        )
        return NPBackupRecord(item: item, windowGroupID: windowGroupID,
                              tabIndex: metadata.tabIndex, timestamp: metadata.timestamp)
    }

    /// 将旧版 metadata 升级为当前格式；升级失败不影响本次恢复。
    private func migrateMetadata(_ metadata: NPBackupMetadata, metadataFileName: String) {
        guard let data = try? JSONEncoder().encode(metadata) else {
            return
        }
        try? data.write(to: backupDirectory.appendingPathComponent(metadataFileName), options: .atomic)
    }

    /// 读取元数据。
    /// - Parameter metadataFileName: 元数据文件名
    /// - Returns: 元数据
    private func loadMetadata(metadataFileName: String) -> NPBackupMetadata? {
        let url = backupDirectory.appendingPathComponent(metadataFileName)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(NPBackupMetadata.self, from: data)
    }

    /// 从元数据文件名解析备份标识。
    /// - Parameter metadataFileName: 元数据文件名
    /// - Returns: 备份标识（非法名返回新 UUID，调用方已保证文件名合法）
    private func backupID(fromMetadataFileName metadataFileName: String) -> UUID {
        let name = (metadataFileName as NSString).deletingPathExtension
        return UUID(uuidString: name) ?? UUID()
    }

    // MARK: - 会话状态与删除

    /// 原子写入会话生命周期状态。
    func writeSessionState(cleanShutdown: Bool) {
        let state = NPBackupSessionState(schemaVersion: 1,
                                         cleanShutdown: cleanShutdown,
                                         timestamp: Date().timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        let stateURL = backupDirectory.appendingPathComponent(Self.sessionStateFileName)
        try? data.write(to: stateURL, options: .atomic)
    }

    /// 删除备份文件对。
    /// - Parameter backupID: 备份标识
    func deleteBackupFiles(backupID: UUID) {
        for ext in [Self.contentFileExtension, Self.metadataFileExtension] {
            let url = backupDirectory.appendingPathComponent("\(backupID.uuidString).\(ext)")
            try? fileManager.removeItem(at: url)
        }
    }

    /// 在同一 IO 队列中删除并同步等待，确保不会被旧快照写入重新创建，
    /// 且调用方返回时缓存已经删除。
    func enqueueDeleteBackupFiles(backupID: UUID) {
        let directory = backupDirectory
        writeQueue.sync {
            let fileManager = FileManager.default
            for ext in [Self.contentFileExtension, Self.metadataFileExtension] {
                let url = directory.appendingPathComponent("\(backupID.uuidString).\(ext)")
                try? fileManager.removeItem(at: url)
            }
        }
    }

    // MARK: - 元数据

    /// 组装备份元数据（含原文件路径与 security-scoped bookmark，供会话恢复重建文件关联）。
    /// - Parameters:
    ///   - document: 目标文档
    ///   - registration: 该文档的注册信息
    ///   - contentHash: 内容摘要（新快照写入时现算，仅元数据写入时沿用上次值）
    /// - Returns: 元数据
    func makeMetadata(for document: NPTextDocument, registration: Registration,
                      contentHash: String) -> NPBackupMetadata {
        NPBackupMetadata(
            schemaVersion: Self.currentSchemaVersion,
            originalFilePath: document.fileURL?.path,
            cursorPosition: registration.cursorPosition,
            encodingRawValue: document.currentEncoding.rawValue,
            lineEndingRawValue: document.currentLineEnding.rawValue,
            windowGroupID: registration.windowGroupID.uuidString,
            tabIndex: registration.tabIndex,
            timestamp: Date().timeIntervalSince1970,
            revision: registration.revision,
            contentHash: contentHash,
            originalFileBookmark: Self.bookmarkBase64(for: document)
        )
    }

    /// 仅重写元数据文件（窗口归属/标签序变化时调用；内容未变，无需重写快照）。
    /// - Parameter document: 目标文档
    func enqueueMetadataWrite(for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard let registration = registrations[key] else {
            return
        }
        let metadata = makeMetadata(for: document, registration: registration,
                                    contentHash: registration.contentHash)
        let backupID = registration.backupID
        let directory = backupDirectory
        writeQueue.async {
            try? Self.writeBackupMetadata(backupID: backupID, metadata: metadata, in: directory)
        }
    }

    // MARK: - 快照写盘原语

    /// 写入备份文件对（后台 IO，目录须已存在，采用临时文件 + 原子替换避免半成品快照）。
    /// - Parameters:
    ///   - backupID: 备份标识
    ///   - content: 文本内容
    ///   - metadata: 元数据
    ///   - directory: 备份目录
    nonisolated static func writeBackupFiles(backupID: UUID, content: String,
                                             metadata: NPBackupMetadata, in directory: URL) throws {
        let fileManager = FileManager.default
        let contentURL = directory.appendingPathComponent("\(backupID.uuidString).\(contentFileExtension)")
        let metadataURL = directory.appendingPathComponent("\(backupID.uuidString).\(metadataFileExtension)")
        let tempContentURL = directory.appendingPathComponent("\(backupID.uuidString).tmp.\(contentFileExtension)")
        let tempMetadataURL = directory.appendingPathComponent("\(backupID.uuidString).tmp.\(metadataFileExtension)")

        let contentData = Data(content.utf8)
        let metadataData = try JSONEncoder().encode(metadata)
        let currentBytes = directoryByteCount(in: directory,
                                               excluding: [contentURL, metadataURL,
                                                           tempContentURL, tempMetadataURL])
        guard currentBytes + contentData.count + metadataData.count <= maxBackupDirectoryBytes else {
            throw NPBackupError.storageLimitExceeded
        }

        try contentData.write(to: tempContentURL, options: .atomic)
        try metadataData.write(to: tempMetadataURL, options: .atomic)

        try replaceOrMove(tempURL: tempContentURL, destinationURL: contentURL,
                          fileManager: fileManager)
        try replaceOrMove(tempURL: tempMetadataURL, destinationURL: metadataURL,
                          fileManager: fileManager)
    }

    /// 仅重写元数据文件（窗口归属/标签序变化时使用；内容快照不变，无需重写）。
    ///
    /// 内容文件尚不存在时跳过，避免产生"只有元数据、没有内容"的孤儿记录
    /// （成对原子写入由 `writeBackupFiles` 负责，启动时会清理孤儿）。
    /// - Parameters:
    ///   - backupID: 备份标识
    ///   - metadata: 元数据
    ///   - directory: 备份目录
    nonisolated static func writeBackupMetadata(backupID: UUID, metadata: NPBackupMetadata,
                                                in directory: URL) throws {
        let fileManager = FileManager.default
        let contentURL = directory.appendingPathComponent("\(backupID.uuidString).\(contentFileExtension)")
        guard fileManager.fileExists(atPath: contentURL.path) else {
            return
        }
        let metadataURL = directory.appendingPathComponent("\(backupID.uuidString).\(metadataFileExtension)")
        let tempMetadataURL = directory.appendingPathComponent("\(backupID.uuidString).tmp.\(metadataFileExtension)")

        let metadataData = try JSONEncoder().encode(metadata)
        let currentBytes = directoryByteCount(in: directory, excluding: [metadataURL, tempMetadataURL])
        guard currentBytes + metadataData.count <= maxBackupDirectoryBytes else {
            throw NPBackupError.storageLimitExceeded
        }

        try metadataData.write(to: tempMetadataURL, options: .atomic)
        try replaceOrMove(tempURL: tempMetadataURL, destinationURL: metadataURL,
                          fileManager: fileManager)
    }

    private nonisolated static func replaceOrMove(tempURL: URL, destinationURL: URL,
                                                  fileManager: FileManager) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL,
                                          backupItemName: nil,
                                          options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }
    }

    private nonisolated static func directoryByteCount(in directory: URL,
                                                       excluding excludedURLs: [URL]) -> Int {
        let excludedPaths = Set(excludedURLs.map(\.path))
        return (try? FileManager.default.contentsOfDirectory(at: directory,
                                                              includingPropertiesForKeys: [.fileSizeKey],
                                                              options: [.skipsHiddenFiles]))?.reduce(0) { total, url in
            guard !excludedPaths.contains(url.path),
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                  let fileSize = values.fileSize else {
                return total
            }
            return total + fileSize
        } ?? 0
    }

    /// 计算快照内容摘要，用于恢复前校验内容与元数据是否属于同一提交。
    nonisolated static func contentHash(for content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
