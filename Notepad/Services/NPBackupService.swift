//
//  NPBackupService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 崩溃恢复项：描述一份可恢复的备份（04 §5.3）。
struct NPBackupItem {
    /// 备份内容文件位置
    let backupContentURL: URL
    /// 原始文件位置；nil 表示从未保存的无标题文档
    let originalFileURL: URL?
    /// 光标位置（UTF-16 偏移量）
    let cursorPosition: Int
    /// 文档编码
    let encoding: String.Encoding
    /// 换行符格式
    let lineEnding: NPLineEnding
}

/// 备份元数据（JSON 序列化；`NPBackupItem` 之外的会话归属信息仅存于元数据）。
struct NPBackupMetadata: Codable {
    /// 原始文件路径（nil = 无标题文档）
    var originalFilePath: String?
    /// 光标位置（UTF-16 偏移量）
    var cursorPosition: Int
    /// 编码 rawValue
    var encodingRawValue: UInt
    /// 换行符 rawValue
    var lineEndingRawValue: String
    /// 窗口归属（标签组标识，会话恢复分组用）
    var windowGroupID: String
    /// 组内标签序
    var tabIndex: Int
    /// 备份时间戳（秒，过期清理依据）
    var timestamp: TimeInterval
}

/// 可恢复记录（`NPBackupItem` + 会话归属，服务内部恢复用）。
struct NPBackupRecord {
    /// 备份项
    let item: NPBackupItem
    /// 窗口归属
    let windowGroupID: UUID
    /// 组内标签序
    let tabIndex: Int
    /// 备份时间戳（恢复排序用）
    let timestamp: TimeInterval
}

/// 自动保存与崩溃恢复服务（PRD FR-003、5.3 节：崩溃时丢失不超过 1 秒的编辑内容）。
///
/// 备份机制与自动保存开关**无关**，始终生效（`01_TECH_SPEC.md` 3.5）：
/// - 内容变化经 `NPTextDocument.onContentDidChange` 触发，**≤1s 节流**（前缘立即写 + 尾缘补写）
///   写入会话备份；备份只服务"未正常关闭"（崩溃/退出）与会话恢复；
/// - 开关 ON 且文档已存盘：除备份外，节流**写回原文件**（`data(ofType:)` 保持原编码/换行符/BOM）；
/// - 正常关闭标签/文档：删除对应备份；退出应用：备份保留，作为下次会话恢复来源。
///
/// 备份目录：`~/Library/Application Support/Notepad/Backups/`，
/// 每文档一对文件：`<UUID>.txt`（内容，UTF-8）+ `<UUID>.json`（元数据）。
@MainActor
final class NPBackupService {

    // MARK: - 单例

    static let shared = NPBackupService()

    // MARK: - 常量

    /// 节流间隔（PRD 5.3：崩溃丢失 ≤1 秒）
    static let throttleInterval: TimeInterval = 1.0
    /// 备份保留天数
    static let retentionDays = 7
    /// 备份内容文件扩展名
    private nonisolated static let contentFileExtension = "txt"
    /// 备份元数据文件扩展名
    private nonisolated static let metadataFileExtension = "json"

    // MARK: - 属性

    /// 备份目录
    private let backupDirectory: URL
    /// 文件管理器
    private let fileManager = FileManager.default

    /// 文档注册信息。
    private struct Registration {
        /// 文档（弱引用）
        weak var document: NPTextDocument?
        /// 备份文件标识
        var backupID: UUID
        /// 窗口归属
        var windowGroupID: UUID
        /// 组内标签序
        var tabIndex: Int
        /// 最近光标位置
        var cursorPosition: Int
        /// 上次写盘时间
        var lastWriteDate: Date
        /// 尾缘写入任务
        var trailingTask: Task<Void, Never>?
        /// 写盘进行中（防止写回清脏触发的重入）
        var isFlushing: Bool
    }

    /// 注册表（按文档对象标识）
    private var registrations: [ObjectIdentifier: Registration] = [:]

    // MARK: - 初始化

    /// 以默认备份目录创建（单例入口）。
    convenience init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                          in: .userDomainMask).first
        let directory = (applicationSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
            .appendingPathComponent("Notepad", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        self.init(backupDirectory: directory)
    }

    /// 以指定备份目录创建（测试注入）。
    /// - Parameter backupDirectory: 备份目录
    init(backupDirectory: URL) {
        self.backupDirectory = backupDirectory
        try? fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    // MARK: - 注册

    /// 注册文档进行自动保存监控（接入内容变化信号并立即建立初始备份）。
    /// - Parameter document: 目标文档
    func registerDocument(_ document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard registrations[key] == nil else {
            return
        }
        registrations[key] = Registration(
            document: document,
            backupID: UUID(),
            windowGroupID: UUID(),
            tabIndex: 0,
            cursorPosition: 0,
            lastWriteDate: .distantPast,
            trailingTask: nil,
            isFlushing: false
        )
        document.onContentDidChange = { [weak self, weak document] in
            guard let self, let document else {
                return
            }
            scheduleBackup(for: document)
        }
        flushBackup(for: document)
    }

    /// 取消注册并删除对应备份（正常关闭标签/文档路径）。
    /// - Parameter document: 目标文档
    func unregisterDocument(_ document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard let registration = registrations.removeValue(forKey: key) else {
            return
        }
        registration.trailingTask?.cancel()
        document.onContentDidChange = nil
        deleteBackupFiles(backupID: registration.backupID)
    }

    /// 立即落盘指定文档的待写内容（取消尾缘任务并同步触发一次刷写）。
    ///
    /// 用于关闭标签前：尾缘节流窗口（≤1s）内的编辑尚未写盘，
    /// 直接注销会丢失这段时间的备份与原文件写回。
    /// - Parameter document: 目标文档
    func flushPendingWrites(for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        registrations[key]?.trailingTask?.cancel()
        registrations[key]?.trailingTask = nil
        flushBackup(for: document)
    }

    /// 立即落盘所有注册文档的待写内容（退出应用前调用）。
    func flushAllPendingWrites() {
        for (key, registration) in registrations {
            registration.trailingTask?.cancel()
            registrations[key]?.trailingTask = nil
            if let document = registration.document {
                flushBackup(for: document)
            }
        }
    }

    /// 停止跟踪文档但**保留**备份文件（关窗/退出路径；备份是下次会话恢复的数据来源）。
    ///
    /// 与 `unregisterDocument`（正常关闭标签，删除备份）相对。
    /// - Parameter document: 目标文档
    func detachDocumentPreservingBackup(_ document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard let registration = registrations.removeValue(forKey: key) else {
            return
        }
        registration.trailingTask?.cancel()
        document.onContentDidChange = nil
    }

    /// 会话恢复时沿用既有备份标识（替换注册时新建的备份，避免恢复后产生重复备份）。
    /// - Parameters:
    ///   - backupID: 既有备份标识（从元数据文件名取得）
    ///   - document: 目标文档
    func adoptBackup(_ backupID: UUID, for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard var registration = registrations[key], registration.backupID != backupID else {
            return
        }
        let freshID = registration.backupID
        registration.backupID = backupID
        registrations[key] = registration
        deleteBackupFiles(backupID: freshID)
        flushBackup(for: document)
    }

    /// 更新窗口归属与标签序（加入标签组 / 拖拽排序后调用）。
    /// - Parameters:
    ///   - windowGroupID: 标签组标识
    ///   - tabIndex: 组内标签序
    ///   - document: 目标文档
    func noteWindowContext(windowGroupID: UUID, tabIndex: Int, for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        registrations[key]?.windowGroupID = windowGroupID
        registrations[key]?.tabIndex = tabIndex
    }

    /// 记录光标位置（备份时随元数据写盘）。
    /// - Parameters:
    ///   - position: 光标位置（UTF-16 偏移量）
    ///   - document: 目标文档
    func noteCursorPosition(_ position: Int, for document: NPTextDocument) {
        registrations[ObjectIdentifier(document)]?.cursorPosition = position
    }

    // MARK: - 恢复

    /// 恢复崩溃前的会话。
    /// 必须包含从未保存的"无标题"文档及其光标位置（PRD FR-003）。
    /// - Returns: 可恢复的备份项列表
    func recoverableItems() -> [NPBackupItem] {
        recoverableRecords().map { record in record.item }
    }

    /// 读取全部有效备份记录（含会话归属，供启动恢复分组）。
    /// - Returns: 备份记录列表（按窗口组、标签序、时间戳排序）
    func recoverableRecords() -> [NPBackupRecord] {
        guard let files = try? fileManager.contentsOfDirectory(atPath: backupDirectory.path) else {
            return []
        }
        var records: [NPBackupRecord] = []
        for file in files where file.hasSuffix(".\(Self.metadataFileExtension)") {
            guard let record = loadRecord(metadataFileName: file) else {
                continue
            }
            records.append(record)
        }
        return records.sorted { lhs, rhs in
            if lhs.windowGroupID.uuidString != rhs.windowGroupID.uuidString {
                return lhs.windowGroupID.uuidString < rhs.windowGroupID.uuidString
            }
            if lhs.tabIndex != rhs.tabIndex {
                return lhs.tabIndex < rhs.tabIndex
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    /// 清理过期备份（保留 7 天）。
    func cleanExpiredBackups() {
        guard let files = try? fileManager.contentsOfDirectory(atPath: backupDirectory.path) else {
            return
        }
        let cutoff = Date().timeIntervalSince1970 - TimeInterval(Self.retentionDays * 24 * 60 * 60)
        for file in files where file.hasSuffix(".\(Self.metadataFileExtension)") {
            guard let metadata = loadMetadata(metadataFileName: file),
                  metadata.timestamp < cutoff else {
                continue
            }
            deleteBackupFiles(backupID: backupID(fromMetadataFileName: file))
        }
    }

    // MARK: - 恢复决策（纯函数）

    /// 已存盘文档恢复决策：备份内容与原文件内容不一致 → 用备份内容并标脏（Win11 语义）。
    /// - Parameters:
    ///   - backupContent: 备份内容
    ///   - fileContent: 原文件内容
    /// - Returns: 是否应以备份内容覆盖
    static func shouldRestoreBackupContent(backupContent: String, fileContent: String) -> Bool {
        backupContent != fileContent
    }

    // MARK: - 节流写盘

    /// 调度备份写入（前缘立即写 + 尾缘补写，任意 1s 窗口内至多一次写盘且不丢最后一笔）。
    ///
    /// 写盘进行中（`isFlushing`）或距上次写入不足 1s 时安排尾缘补写——
    /// 绝不丢弃变化，保证崩溃丢失 ≤ 1s（PRD 5.3）。
    /// - Parameter document: 目标文档
    private func scheduleBackup(for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard let registration = registrations[key] else {
            return
        }
        let elapsed = Date().timeIntervalSince(registration.lastWriteDate)
        if !registration.isFlushing, elapsed >= Self.throttleInterval {
            flushBackup(for: document)
            return
        }
        guard registration.trailingTask == nil else {
            return
        }
        let delay = max(Self.throttleInterval - elapsed, 0.05)
        registrations[key]?.trailingTask = Task { [weak self, weak document] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run { [weak self] in
                guard let document else {
                    return
                }
                self?.flushBackup(for: document)
            }
        }
    }

    /// 立即写盘：内容 + 元数据（IO 后台执行）；开关 ON 且已存盘时同步写回原文件。
    /// - Parameter document: 目标文档
    private func flushBackup(for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard var registration = registrations[key] else {
            return
        }
        registration.isFlushing = true
        registration.trailingTask = nil
        registration.lastWriteDate = Date()
        registrations[key] = registration

        let backupID = registration.backupID
        let metadata = NPBackupMetadata(
            originalFilePath: document.fileURL?.path,
            cursorPosition: registration.cursorPosition,
            encodingRawValue: document.currentEncoding.rawValue,
            lineEndingRawValue: document.currentLineEnding.rawValue,
            windowGroupID: registration.windowGroupID.uuidString,
            tabIndex: registration.tabIndex,
            timestamp: Date().timeIntervalSince1970
        )
        let content = document.textContent
        let directory = backupDirectory
        Task.detached(priority: .utility) { [weak self] in
            Self.writeBackupFiles(backupID: backupID, content: content,
                                  metadata: metadata, in: directory)
            await MainActor.run { [weak self] in
                self?.registrations[key]?.isFlushing = false
            }
        }

        // 开关 ON 且已存盘：节流写回原文件（保持原编码/换行符/BOM）
        if NPPreferences.shared.isAutoSaveEnabled, let fileURL = document.fileURL {
            writeBackToOriginal(document: document, fileURL: fileURL)
        }
    }

    /// 写回原文件并清除脏状态（`isFlushing` 标志阻止清脏触发的重入调度）。
    /// - Parameters:
    ///   - document: 目标文档
    ///   - fileURL: 原文件位置
    private func writeBackToOriginal(document: NPTextDocument, fileURL: URL) {
        do {
            let data = try document.data(ofType: "public.plain-text")
            Task.detached(priority: .utility) {
                try? data.write(to: fileURL, options: .atomic)
            }
            document.updateChangeCount(.changeCleared)
        } catch {
            // 编码失败等：跳过写回，会话备份仍在
        }
    }

    // MARK: - 私有：文件操作

    /// 写入备份文件对（后台 IO，目录须已存在）。
    /// - Parameters:
    ///   - backupID: 备份标识
    ///   - content: 文本内容
    ///   - metadata: 元数据
    ///   - directory: 备份目录
    private nonisolated static func writeBackupFiles(backupID: UUID, content: String,
                                                     metadata: NPBackupMetadata, in directory: URL) {
        let contentURL = directory.appendingPathComponent("\(backupID.uuidString).\(contentFileExtension)")
        let metadataURL = directory.appendingPathComponent("\(backupID.uuidString).\(metadataFileExtension)")
        try? content.write(to: contentURL, atomically: true, encoding: .utf8)
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    /// 删除备份文件对。
    /// - Parameter backupID: 备份标识
    private func deleteBackupFiles(backupID: UUID) {
        for ext in [Self.contentFileExtension, Self.metadataFileExtension] {
            let url = backupDirectory.appendingPathComponent("\(backupID.uuidString).\(ext)")
            try? fileManager.removeItem(at: url)
        }
    }

    /// 读取备份记录（元数据与内容文件均存在才有效）。
    /// - Parameter metadataFileName: 元数据文件名
    /// - Returns: 备份记录
    private func loadRecord(metadataFileName: String) -> NPBackupRecord? {
        guard let metadata = loadMetadata(metadataFileName: metadataFileName) else {
            return nil
        }
        let backupID = backupID(fromMetadataFileName: metadataFileName)
        let contentURL = backupDirectory
            .appendingPathComponent("\(backupID.uuidString).\(Self.contentFileExtension)")
        guard fileManager.fileExists(atPath: contentURL.path),
              let windowGroupID = UUID(uuidString: metadata.windowGroupID) else {
            return nil
        }
        let item = NPBackupItem(
            backupContentURL: contentURL,
            originalFileURL: metadata.originalFilePath.map { path in URL(fileURLWithPath: path) },
            cursorPosition: metadata.cursorPosition,
            encoding: String.Encoding(rawValue: metadata.encodingRawValue),
            lineEnding: NPLineEnding(rawValue: metadata.lineEndingRawValue) ?? .lf
        )
        return NPBackupRecord(item: item, windowGroupID: windowGroupID,
                              tabIndex: metadata.tabIndex, timestamp: metadata.timestamp)
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
}
