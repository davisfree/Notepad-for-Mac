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
    /// 原文件的 security-scoped bookmark（沙盒下重启后重新获得读写权限所需；nil = 无）
    let originalFileBookmark: Data?
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
    /// 原文件的 security-scoped bookmark（base64）；旧格式缺失时仅依赖路径
    var originalFileBookmark: String?
}

/// 会话生命周期标记。`cleanShutdown == false` 表示上次进程未完成正常退出流程。
/// - Note: `internal` 而非 `private`：会话状态落盘在 `NPBackupService+Storage.swift`。
struct NPBackupSessionState: Codable {
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
    nonisolated static let contentFileExtension = "txt"
    /// 备份元数据文件扩展名
    nonisolated static let metadataFileExtension = "json"
    /// 会话生命周期文件名
    nonisolated static let sessionStateFileName = "session-state.json"
    /// 单文档快照最大 UTF-8 字节数（10 MiB）
    static let maxSnapshotBytes = 10 * 1024 * 1024
    /// 会话缓存目录最大占用（100 MiB）
    static let maxBackupDirectoryBytes = 100 * 1024 * 1024

    // MARK: - 属性

    /// 备份目录
    let backupDirectory: URL
    /// 文件管理器
    let fileManager = FileManager.default
    /// 串行化快照提交，避免旧写入晚完成而覆盖新内容
    let writeQueue = DispatchQueue(label: "com.notepad.backup.write", qos: .utility)

    /// 文档注册信息。
    ///
    /// - Note: 非 `private`：元数据组装与仅元数据写入拆分在
    ///   `NPBackupService+Storage.swift`（详见该文件头部说明）。
    struct Registration {
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
        /// 上次写入内容的内容摘要（仅重写元数据时可复用，避免重复读内容）
        var contentHash: String
        /// 尾缘写入任务
        var trailingTask: Task<Void, Never>?
        /// 写盘进行中（防止写回清脏触发的重入）
        var isFlushing: Bool
    }

    /// 注册表（按文档对象标识）。
    ///
    /// - Note: 非 `private`，供 `NPBackupService+Storage.swift` 的扩展访问。
    var registrations: [ObjectIdentifier: Registration] = [:]

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
            contentHash: "",
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
    ///
    /// 变化时**立即重写元数据文件**：`windowGroupID` 决定重启后“几个窗口”、
    /// `tabIndex` 决定组内标签序。只改内存会在异常终止（关机/登出，不跑
    /// `applicationShouldTerminate` 的整批刷盘）后留下按文档随机分配的旧分组，
    /// 同一窗口的 N 个标签就会在下次启动散成 N 个窗口。
    /// - Parameters:
    ///   - windowGroupID: 标签组标识
    ///   - tabIndex: 组内标签序
    ///   - document: 目标文档
    func noteWindowContext(windowGroupID: UUID, tabIndex: Int, for document: NPTextDocument) {
        let key = ObjectIdentifier(document)
        guard var registration = registrations[key] else {
            return
        }
        let didChange = registration.windowGroupID != windowGroupID
            || registration.tabIndex != tabIndex
        registration.windowGroupID = windowGroupID
        registration.tabIndex = tabIndex
        registrations[key] = registration
        guard didChange else {
            return
        }
        enqueueMetadataWrite(for: document)
    }

    /// 记录光标位置（备份时随元数据写盘）。
    /// - Parameters:
    ///   - position: 光标位置（UTF-16 偏移量）
    ///   - document: 目标文档
    func noteCursorPosition(_ position: Int, for document: NPTextDocument) {
        registrations[ObjectIdentifier(document)]?.cursorPosition = position
    }

    // MARK: - 恢复

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

    // MARK: - 恢复决策（纯函数）

    /// 当前元数据格式版本（v3 起记录原文件 security-scoped bookmark）。
    static let currentSchemaVersion = 3

    /// 生成原文件的 security-scoped bookmark 并做 base64 编码。
    ///
    /// 沙盒的"用户选择文件"权限只对当前进程有效：仅记录路径时，重启恢复会因沙盒拒绝
    /// 而打不开原文件，只能退化为"未命名"文档（内容在、文件名丢失）。
    /// 非沙盒环境（如 swiftc 直编 / 测试宿主）无法创建 security-scoped bookmark，
    /// 此时回落普通 bookmark；两者都失败返回 nil（恢复时继续依赖路径）。
    /// - Parameter document: 目标文档
    /// - Returns: base64 字符串（无原文件或创建失败时为 nil）
    static func bookmarkBase64(for document: NPTextDocument) -> String? {
        guard let fileURL = document.fileURL else {
            return nil
        }
        let data = (try? fileURL.bookmarkData(options: [.withSecurityScope],
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: nil))
            ?? (try? fileURL.bookmarkData(options: [],
                                          includingResourceValuesForKeys: nil,
                                          relativeTo: nil))
        return data?.base64EncodedString()
    }

    /// 解析原文件 URL：优先 security-scoped bookmark（沙盒重启后仍可访问），失败回落路径。
    /// - Parameters:
    ///   - path: 元数据记录的原文件路径
    ///   - bookmark: 元数据记录的 bookmark（已 base64 解码）
    /// - Returns: 可用于打开文档的 URL（无原文件时为 nil）
    static func resolveFileURL(path: String?, bookmark: Data?) -> URL? {
        if let bookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [.withSecurityScope],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) {
                // 沙盒扩展必须显式开启，且恢复出的文档整个会话都要写原文件，
                // 故此处不配对 stop（访问权随进程结束释放）。
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
            // 非沙盒环境（测试宿主 / swiftc 直编）记录的是普通 bookmark
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [],
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) {
                return url
            }
        }
        return path.map { URL(fileURLWithPath: $0) }
    }

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
        let contentHash = Self.contentHash(for: content)
        let metadata = makeMetadata(for: document, registration: registration, contentHash: contentHash)
        // 记录内容摘要，供后续仅元数据写入复用（窗口归属变化时无需重写快照）
        registration.contentHash = contentHash
        registrations[key] = registration
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

    // MARK: - 失败上报

    private func postBackupFailure(_ error: NPBackupError) {
        NotificationCenter.default.post(
            name: NPNotificationNames.backupDidFail,
            object: self,
            userInfo: [NPNotificationNames.backupErrorKey: error.identifier]
        )
    }

}
