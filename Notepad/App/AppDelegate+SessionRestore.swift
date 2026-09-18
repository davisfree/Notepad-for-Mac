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
            if let existing = windowControllersByGroup[record.windowGroupID] {
                existing.addTab(for: document)
                windowController = existing
            } else {
                windowController = NPTabWindowManager.shared.openInNewWindow(document)
                windowControllersByGroup[record.windowGroupID] = windowController
            }
            // 沿用既有备份标识（避免恢复后产生重复备份），并恢复光标位置
            if let backupID = UUID(uuidString: record.item.backupContentURL.deletingPathExtension().lastPathComponent) {
                NPBackupService.shared.adoptBackup(backupID, for: document)
            }
            if let entry = windowController.tabBarController.entries.last,
               entry.document === document {
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
        guard let originalFileURL = record.item.originalFileURL else {
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
        // 已存盘文档：从原路径打开
        guard let document = try? NPTextDocument(contentsOf: originalFileURL,
                                                 ofType: "public.plain-text") else {
            // 原文件已丢失：退化为未命名文档 + 备份内容；仅非空内容标脏
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
        return document
    }

    /// 提示用户原文件较新，因此恢复时保留了原文件内容。
    private func presentRestoreConflictNotification() {
        NPUserNotificationService.shared.deliver(
            title: NSLocalizedString("Backup.RestoreConflict.Title", comment: "恢复冲突标题"),
            body: NSLocalizedString("Backup.RestoreConflict.Message", comment: "恢复冲突说明")
        )
    }
}
