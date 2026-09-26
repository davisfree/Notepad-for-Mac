//
//  AppDelegate+SessionRestore.swift
//  Notepad
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 会话恢复（PRD FR-003）：启动时按窗口归属重建标签并还原未保存内容与光标。
///
/// 从 `AppDelegate.swift` 拆出——启动恢复是一块边界清晰、只依赖 `NPBackupService`
/// 与会话记录的独立职责，而主文件已接近 SwiftLint `file_length` / `type_body_length`
/// 阈值。与主文件共用的两个窗口/文档工厂助手（`makeTrackedUntitledDocument`、
/// `openUntitledWindowIfNoDocuments`）因此为 `internal` 而非 `private`。
///
/// 恢复三态（见 `restoreDocument`）：未命名 → 备份内容标脏；已存盘有改动 → 备份内容标脏；
/// 已存盘无改动 → 原样保留，原文件较新时提示冲突。
extension AppDelegate {

    /// 恢复上次会话：按窗口归属分组恢复标签（内容 + 光标）。
    /// - Parameter records: 备份记录（已按组/标签序/时间戳排序）
    func restoreSession(from records: [NPBackupRecord]) {
        var windowControllersByGroup: [UUID: NPEditorWindowController] = [:]
        for record in records {
            guard let document = restoreDocument(for: record) else {
                continue
            }
            let windowController: NPEditorWindowController
            if let host = NPTabWindowManager.shared.windowController(containing: document) {
                // 文档已在窗口中（系统恢复/最近使用先打开）：复用，不重复插入标签
                windowController = host
            } else if let existing = windowControllersByGroup[record.windowGroupID] {
                // 显式 `.trailing`：会话恢复必须按记录的标签序还原，
                // 不能走"新建标签页插到最左端"的路径
                existing.addTab(for: document, position: .trailing)
                windowController = existing
            } else {
                windowController = NPTabWindowManager.shared.openInNewWindow(document)
                windowControllersByGroup[record.windowGroupID] = windowController
            }
            // 沿用既有备份标识（避免恢复后产生重复备份），并恢复光标位置
            if let backupID = UUID(uuidString: record.item.backupContentURL.deletingPathExtension().lastPathComponent) {
                NPBackupService.shared.adoptBackup(backupID, for: document)
            }
            // 按文档身份定位装配：不用 `entries.last`（插入位置可变，末位未必是本文档）
            if let entry = windowController.tabBarController.entries.first(where: {
                $0.document === document
            }) {
                let length = (document.textContent as NSString).length
                let location = min(max(record.item.cursorPosition, 0), length)
                entry.editorController.editorView.selectedRange = NSRange(location: location, length: 0)
            }
        }
        // 兜底：全部恢复失败时仍保证一个窗口
        openUntitledWindowIfNoDocuments()
    }

    /// 恢复单个文档（三态：未命名 → 备份内容标脏；已存盘有改动 → 备份内容标脏；已存盘无改动 → 原样）。
    /// - Parameter record: 备份记录
    /// - Returns: 恢复的文档（原文件与备份均不可读时为 nil）
    private func restoreDocument(for record: NPBackupRecord) -> NPTextDocument? {
        let backupContent = try? String(contentsOf: record.item.backupContentURL, encoding: .utf8)
        // 原文件位置：优先 security-scoped bookmark（沙盒下重启后路径已不可读），回落路径。
        // 两者都拿不到才是真正的"未命名文档"。
        guard let originalFileURL = NPBackupService.resolveFileURL(
            path: record.item.originalFileURL?.path,
            bookmark: record.item.originalFileBookmark
        ) else {
            // 未命名文档：恢复备份内容与光标；仅非空内容标脏（空文档与新建无异，不应提示未保存）
            guard let document = try? makeTrackedUntitledDocument(), let backupContent else {
                return nil
            }
            document.textContent = backupContent
            if !backupContent.isEmpty {
                document.updateChangeCount(.changeDone)
            }
            return document
        }
        // 已存盘文档：优先复用**已打开的同一文件**（系统状态恢复/最近使用/Dock 拖入
        // 可能先打开它），否则从原位置打开（bookmark 已开启沙盒访问权）。
        // 不复用会产生同一文件两个文档、两个标签（关机重启回归根因）。
        if let opened = openedDocument(forFileAt: originalFileURL) {
            applyBackupContent(record: record, backupContent: backupContent,
                               to: opened, originalFileURL: originalFileURL)
            return opened
        }
        guard let document = try? NPTextDocument(contentsOf: originalFileURL,
                                                 ofType: "public.plain-text") else {
            // 原文件已丢失或不可访问：退化为未命名文档 + 备份内容；仅非空内容标脏
            guard let fallback = try? makeTrackedUntitledDocument(), let backupContent else {
                return nil
            }
            fallback.textContent = backupContent
            if !backupContent.isEmpty {
                fallback.updateChangeCount(.changeDone)
            }
            return fallback
        }
        let controller = NSDocumentController.shared
        if !controller.documents.contains(where: { $0 === document }) {
            controller.addDocument(document)
        }
        applyBackupContent(record: record, backupContent: backupContent,
                           to: document, originalFileURL: originalFileURL)
        return document
    }

    /// 查找已打开的同一文件的文档。
    /// - Parameter fileURL: 原文件位置
    /// - Returns: 已打开的文档（无则 `nil`）
    private func openedDocument(forFileAt fileURL: URL) -> NPTextDocument? {
        NSDocumentController.shared.documents
            .compactMap { $0 as? NPTextDocument }
            .first { $0.fileURL?.path == fileURL.path }
    }

    /// 按"备份较新则用备份内容"的决策将备份内容应用到文档（含冲突提示）。
    /// - Parameters:
    ///   - record: 备份记录
    ///   - backupContent: 备份内容（读取失败时为 nil）
    ///   - document: 目标文档
    ///   - originalFileURL: 原文件位置
    private func applyBackupContent(record: NPBackupRecord, backupContent: String?,
                                    to document: NPTextDocument, originalFileURL: URL) {
        let fileModificationDate = try? originalFileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        if let backupContent,
           NPBackupService.restoreDecision(
               backupContent: backupContent,
               fileContent: document.textContent,
               backupTimestamp: record.timestamp,
               fileModificationDate: fileModificationDate
           ) == .useBackup {
            document.textContent = backupContent
            document.updateChangeCount(.changeDone)
        } else if let backupContent,
                  backupContent != document.textContent,
                  fileModificationDate != nil {
            presentRestoreConflictNotification()
        }
    }

    /// 提示用户原文件较新，因此恢复时保留了原文件内容。
    private func presentRestoreConflictNotification() {
        NPUserNotificationService.shared.deliver(
            title: NSLocalizedString("Backup.RestoreConflict.Title", comment: "恢复冲突标题"),
            body: NSLocalizedString("Backup.RestoreConflict.Message", comment: "恢复冲突说明")
        )
    }
}
