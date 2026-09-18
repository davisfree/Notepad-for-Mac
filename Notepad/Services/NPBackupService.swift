//
//  NPBackupService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation
import CryptoKit

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
    /// 元数据格式版本；旧格式缺失时按兼容格式读取
    var schemaVersion: Int?
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
    /// 文档快照版本；旧格式缺失时视为未版本化
    var revision: UInt64?
    /// UTF-8 内容的 SHA-256；旧格式缺失时跳过校验
    var contentHash: String?
}

/// 会话生命周期标记。`cleanShutdown == false` 表示上次进程未完成正常退出流程。
private struct NPBackupSessionState: Codable {
    var schemaVersion: Int
    var cleanShutdown: Bool
    var timestamp: TimeInterval
}

/// 会话缓存写入错误（用于非阻塞地暴露缓存失败原因）。
enum NPBackupError: Error, Equatable {
    case snapshotTooLarge
    case storageLimitExceeded
    case writeFailed

    var identifier: String {
        switch self {
        case .snapshotTooLarge:
            return "snapshotTooLarge"
        case .storageLimitExceeded:
            return "storageLimitExceeded"
        case .writeFailed:
            return "writeFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .snapshotTooLarge:
            return NSLocalizedString("Backup.Error.SnapshotTooLarge", comment: "缓存文件过大")
        case .storageLimitExceeded:
            return NSLocalizedString("Backup.Error.StorageLimitExceeded", comment: "缓存目录已满")
        case .writeFailed:
            return NSLocalizedString("Backup.Error.WriteFailed", comment: "缓存写入失败")
        }
    }
}

enum NPBackupRestoreDecision: Equatable {
    case useOriginal
    case useBackup
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

/// 会话缓存与崩溃恢复服务（PRD FR-003、5.3 节：崩溃时丢失不超过 1 秒的编辑内容）。
///
/// 备份机制始终生效，不提供开关（`01_TECH_SPEC.md` 3.5）：
/// - 内容变化经 `NPTextDocument.onContentDidChange` 触发，**≤1s 节流**（前缘立即写 + 尾缘补写）
///   写入会话备份；备份只服务"未正常关闭"（崩溃/退出）与会话恢复；
/// - 原文件只由用户显式保存更新；缓存不会覆盖用户文件；
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
    /// 会话生命周期文件名
    private nonisolated static let sessionStateFileName = "session-state.json"
    /// 单文档快照最大 UTF-8 字节数（10 MiB）
    static let maxSnapshotBytes = 10 * 1024 * 1024
    /// 会话缓存目录最大占用（100 MiB）
    private static let maxBackupDirectoryBytes = 100 * 1024 * 1024

    // MARK: - 属性

    /// 备份目录
    private let backupDirectory: URL
    /// 文件管理器
    private let fileManager = FileManager.default
    /// 串行化快照提交，避免旧写入晚完成而覆盖新内容
    private let writeQueue = DispatchQueue(label: "com.notepad.backup.write", qos: .utility)

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
        /// 已提交或正在提交的快照版本
        var revision: UInt64
        /// 尾缘写入任务
        var trailingTask: Task<Void, Never>?
        /// 写盘进行中（防止写回清脏触发的重入）
        var isFlushing: Bool
    }

    /// 注册表（按文档对象标识）
    private var registrations: [ObjectIdentifier: Registration] = [:]

    /// 是否处于退出流程（`markTerminating` 置位）。
    /// 供关窗路径区分"用户手动关窗"（删除备份）与"退出流程关窗"（保留备份）。
    private(set) var isTerminating = false
    /// 上一次会话是否完成正常退出。
    private(set) var previousSessionEndedCleanly = true
    /// 最近一次快照写入错误；成功提交新快照后清除。
    private(set) var lastBackupError: NPBackupError?

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

    // MARK: - 会话生命周期

    /// 开始新会话并返回上一次会话是否正常退出。
    /// 缺少状态文件按首次启动处理；损坏状态按异常退出处理，以保守保留恢复数据。
    @discardableResult
    func beginSession() -> Bool {
        let stateURL = backupDirectory.appendingPathComponent(Self.sessionStateFileName)
        let previousState: NPBackupSessionState?
        if let data = try? Data(contentsOf: stateURL) {
            previousState = try? JSONDecoder().decode(NPBackupSessionState.self, from: data)
        } else {
            previousState = nil
        }
        let stateExists = FileManager.default.fileExists(atPath: stateURL.path)
        let previousClean = stateExists ? (previousState?.cleanShutdown ?? false) : true
        previousSessionEndedCleanly = previousClean
        writeSessionState(cleanShutdown: false)
        return previousClean
    }

    /// 标记当前会话已完成正常退出。
    func markCleanShutdown() {
        writeSessionState(cleanShutdown: true)
    }

    /// 等待已排队的快照文件写入完成。
    func waitForPendingWrites() {
        writeQueue.sync { }
    }

    // MARK: - 注册

    /// 注册文档进行会话缓存监控（接入内容变化信号并立即建立初始备份）。
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
            revision: 0,
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
        enqueueDeleteBackupFiles(backupID: registration.backupID)
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
        waitForPendingWrites()
    }

    /// 标记进入退出流程（退出钩子调用；此后关窗保留备份，供下次启动会话恢复）。
    func markTerminating() {
        isTerminating = true
    }

    /// 停止跟踪文档但**保留**备份文件（退出流程关窗路径；备份是下次会话恢复的数据来源）。
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
        enqueueDeleteBackupFiles(backupID: freshID)
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

    /// 退出清理：保留当前仍打开文档（已注册标签）的备份，删除其余备份文件。
    ///
    /// 会话恢复的正确语义是"退出时仍打开的窗口/标签"。正常使用中关窗即删除备份
    /// （见 `detachAllTabsForWindowClose`），退出时这里兜底清理崩溃残留、旧版本遗留
    /// 等不在注册表中的备份，避免下次启动恢复出已关闭的窗口。
    /// 注册表为空（如登出/关机流程已先行关闭窗口、文档全部摘除）时**不删除任何文件**，
    /// 防止把退出时仍打开、但已由窗口关闭流程保留的备份误删。
    func pruneBackupsForQuit() {
        let activeIDs = Set(registrations.values.map { $0.backupID })
        guard !activeIDs.isEmpty,
              let files = try? fileManager.contentsOfDirectory(atPath: backupDirectory.path) else {
            return
        }
        for file in files {
            if file == Self.sessionStateFileName {
                continue
            }
            let name = (file as NSString).deletingPathExtension
            guard let backupID = UUID(uuidString: name),
                  activeIDs.contains(backupID) else {
                try? fileManager.removeItem(at: backupDirectory.appendingPathComponent(file))
                continue
            }
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

    // MARK: - 恢复决策（纯函数）

    /// 已存盘文档恢复决策：备份内容与原文件内容不一致 → 用备份内容并标脏（Win11 语义）。
    /// - Parameters:
    ///   - backupContent: 备份内容
    ///   - fileContent: 原文件内容
    /// - Returns: 是否应以备份内容覆盖
    static func shouldRestoreBackupContent(backupContent: String, fileContent: String) -> Bool {
        backupContent != fileContent
    }

    /// 冲突恢复决策：只有缓存内容不同且不早于原文件时才使用缓存。
    /// 无法读取原文件修改时间时保守沿用旧行为，优先恢复缓存内容。
    static func restoreDecision(backupContent: String, fileContent: String,
                                backupTimestamp: TimeInterval,
                                fileModificationDate: Date?) -> NPBackupRestoreDecision {
        guard backupContent != fileContent else {
            return .useOriginal
        }
        guard let fileModificationDate else {
            return .useBackup
        }
        return backupTimestamp >= fileModificationDate.timeIntervalSince1970 ? .useBackup : .useOriginal
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

    /// 立即写盘：仅写入内容与元数据快照（IO 后台执行）。
    /// - Parameter document: 目标文档
    private func flushBackup(for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard var registration = registrations[key] else {
            return
        }
        registration.revision &+= 1
        registration.isFlushing = true
        registration.trailingTask = nil
        registration.lastWriteDate = Date()
        registrations[key] = registration

        let backupID = registration.backupID
        let revision = registration.revision
        let content = document.textContent
        guard Data(content.utf8).count <= Self.maxSnapshotBytes else {
            lastBackupError = .snapshotTooLarge
            registration.isFlushing = false
            registrations[key] = registration
            postBackupFailure(.snapshotTooLarge)
            return
        }
        let metadata = NPBackupMetadata(
            schemaVersion: 2,
            originalFilePath: document.fileURL?.path,
            cursorPosition: registration.cursorPosition,
            encodingRawValue: document.currentEncoding.rawValue,
            lineEndingRawValue: document.currentLineEnding.rawValue,
            windowGroupID: registration.windowGroupID.uuidString,
            tabIndex: registration.tabIndex,
            timestamp: Date().timeIntervalSince1970,
            revision: revision,
            contentHash: Self.contentHash(for: content)
        )
        let directory = backupDirectory
        writeQueue.async { [weak self] in
            do {
                try Self.writeBackupFiles(backupID: backupID, content: content,
                                          metadata: metadata, in: directory)
                Task { @MainActor [weak self] in
                    guard let self, var current = self.registrations[key],
                          current.revision == revision else {
                        return
                    }
                    current.lastWriteDate = Date()
                    current.isFlushing = false
                    self.registrations[key] = current
                    self.lastBackupError = nil
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, var current = self.registrations[key],
                          current.revision == revision else {
                        return
                    }
                    current.isFlushing = false
                    self.registrations[key] = current
                    let backupError = (error as? NPBackupError) ?? .writeFailed
                    self.lastBackupError = backupError
                    self.postBackupFailure(backupError)
                }
            }
        }
    }

    // MARK: - 私有：文件操作

    /// 原子写入会话生命周期状态。
    private func writeSessionState(cleanShutdown: Bool) {
        let state = NPBackupSessionState(schemaVersion: 1,
                                         cleanShutdown: cleanShutdown,
                                         timestamp: Date().timeIntervalSince1970)
        guard let data = try? JSONEncoder().encode(state) else {
            return
        }
        let stateURL = backupDirectory.appendingPathComponent(Self.sessionStateFileName)
        try? data.write(to: stateURL, options: .atomic)
    }

    private func postBackupFailure(_ error: NPBackupError) {
        NotificationCenter.default.post(
            name: NPNotificationNames.backupDidFail,
            object: self,
            userInfo: [NPNotificationNames.backupErrorKey: error.identifier]
        )
    }

    /// 写入备份文件对（后台 IO，目录须已存在，采用临时文件 + 原子替换避免半成品快照）。
    /// - Parameters:
    ///   - backupID: 备份标识
    ///   - content: 文本内容
    ///   - metadata: 元数据
    ///   - directory: 备份目录
    private nonisolated static func writeBackupFiles(backupID: UUID, content: String,
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
    private nonisolated static func contentHash(for content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// 删除备份文件对。
    /// - Parameter backupID: 备份标识
    private func deleteBackupFiles(backupID: UUID) {
        for ext in [Self.contentFileExtension, Self.metadataFileExtension] {
            let url = backupDirectory.appendingPathComponent("\(backupID.uuidString).\(ext)")
            try? fileManager.removeItem(at: url)
        }
    }

    /// 在同一 IO 队列中删除并同步等待，确保不会被旧快照写入重新创建，
    /// 且调用方返回时缓存已经删除。
    private func enqueueDeleteBackupFiles(backupID: UUID) {
        let directory = backupDirectory
        writeQueue.sync {
            let fileManager = FileManager.default
            for ext in [Self.contentFileExtension, Self.metadataFileExtension] {
                let url = directory.appendingPathComponent("\(backupID.uuidString).\(ext)")
                try? fileManager.removeItem(at: url)
            }
        }
    }

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
        guard metadata.originalFilePath == nil || !metadata.originalFilePath!.isEmpty else {
            return nil
        }
        if metadata.schemaVersion != 2 || metadata.revision == nil || metadata.contentHash == nil {
            metadata.schemaVersion = 2
            metadata.revision = metadata.revision ?? 0
            metadata.contentHash = Self.contentHash(for: content)
            migrateMetadata(metadata, metadataFileName: metadataFileName)
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
}
