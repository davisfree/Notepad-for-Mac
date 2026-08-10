//
//  NPTextDocument.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// 纯文本文档模型，封装编码、换行符、内容管理。
///
/// 继承 `NSDocument` 自动获得：自动保存、版本浏览、崩溃恢复。
/// 检测逻辑委托 `NPEncodingManager` / `NPLineEndingManager`，本类只维护文档状态。
/// 内存中 `textContent` 统一以 LF（`\n`）存储，保存时按 `currentLineEnding` 转换。
final class NPTextDocument: NSDocument {

    // MARK: - 属性

    /// 当前文本内容（主线程访问；换行符统一为 LF）
    var textContent: String = ""

    /// 当前文件编码
    var currentEncoding: String.Encoding = .utf8

    /// 当前换行符格式
    var currentLineEnding: NPLineEnding = .lf

    /// 文件是否带 BOM（UTF-8/UTF-16/UTF-32）
    var hasBOM: Bool = false

    /// 是否只读（打开超过 10MB 的文件时设定，PRD FR-001；编辑器禁用修改、保存动作报错）
    private(set) var isReadOnly = false

    /// 是否有未保存的更改（包装 `NSDocument.isDocumentEdited`，不单独维护状态）
    var hasUnsavedChanges: Bool {
        isDocumentEdited
    }

    /// 文件原始编码（打开时检测到的，用于保存时默认选择）
    private(set) var originalEncoding: String.Encoding = .utf8

    /// 显示名变化回调（标签标题同步；闭包注入避免 Document 层依赖 UI）
    var onDisplayNameChange: (() -> Void)?

    /// 脏状态变化回调（标签未保存圆点同步）
    var onEditedStateChange: ((Bool) -> Void)?

    /// 内容变化回调（自动保存备份触发点；由 `NPBackupService.registerDocument` 独占接入）
    var onContentDidChange: (() -> Void)?

    /// 显示名变更时触发回调（保存/重命名后同步标签与窗口标题）。
    override var displayName: String? {
        didSet { onDisplayNameChange?() }
    }

    /// 脏状态变更时触发回调（`updateChangeCount` 是所有脏状态迁移的统一入口）。
    /// - Parameter changeType: 变更类型
    override func updateChangeCount(_ changeType: NSDocument.ChangeType) {
        super.updateChangeCount(changeType)
        onEditedStateChange?(isDocumentEdited)
        onContentDidChange?()
    }

    // MARK: - 初始化

    override init() {
        super.init()
    }

    // MARK: - 编码 / 换行符切换

    /// 切换文档编码（先验证内容可按目标编码序列化，再更新状态并标记文档已修改）。
    /// - Parameter encoding: 目标编码
    /// - Throws: `NPEncodingError.conversionFailed`
    func changeEncoding(to encoding: String.Encoding) throws {
        guard encoding != currentEncoding else {
            return
        }
        _ = try NPEncodingManager.shared.encode(textContent, as: encoding, includeBOM: hasBOM)
        currentEncoding = encoding
        updateChangeCount(.changeDone)
        NotificationCenter.default.post(
            name: NPNotificationNames.documentEncodingDidChange,
            object: self,
            userInfo: [NPNotificationNames.encodingKey: NSNumber(value: encoding.rawValue)]
        )
    }

    /// 切换换行符格式（转换内容中的换行符并标记文档已修改）。
    /// - Parameter lineEnding: 目标换行符格式
    func changeLineEnding(to lineEnding: NPLineEnding) {
        guard lineEnding != currentLineEnding else {
            return
        }
        textContent = NPLineEndingManager.normalize(textContent, to: lineEnding)
        currentLineEnding = lineEnding
        updateChangeCount(.changeDone)
        NotificationCenter.default.post(
            name: NPNotificationNames.documentLineEndingDidChange,
            object: self,
            userInfo: [NPNotificationNames.lineEndingKey: lineEnding.rawValue]
        )
    }

    // MARK: - NSDocument 读写

    /// 从数据读取文档：检测编码与 BOM，剥离 BOM 后解码，换行符归一为 LF 存储。
    /// 超过 10MB 的文件标记为只读（PRD FR-001、01 §3.3）。
    /// - Parameters:
    ///   - data: 原始文件数据
    ///   - typeName: 文档类型 UTI
    /// - Throws: `NPEncodingError.undetectable` / `NPEncodingError.conversionFailed`
    override func read(from data: Data, ofType typeName: String) throws {
        isReadOnly = data.count > NPConstants.largeFileThreshold
        let result = try NPEncodingManager.shared.detect(from: data)
        var payload = data
        if result.hasBOM, let bom = NPEncodingManager.bomBytes(for: result.encoding) {
            payload = data.dropFirst(bom.count)
        }
        let decoded = try NPEncodingManager.shared.decode(payload, as: result.encoding)
        currentLineEnding = NPLineEndingManager.detect(in: decoded)
        textContent = NPLineEndingManager.normalize(decoded, to: .lf)
        currentEncoding = result.encoding
        originalEncoding = result.encoding
        hasBOM = result.hasBOM
    }

    /// 序列化文档用于保存：先按 `currentLineEnding` 转换换行符，再按 `currentEncoding` + `hasBOM` 编码。
    /// - Parameter typeName: 文档类型 UTI
    /// - Returns: 编码后的文件数据
    /// - Throws: `NPError.documentIsReadOnly`（只读模式）/ `NPEncodingError.conversionFailed`
    override func data(ofType typeName: String) throws -> Data {
        guard !isReadOnly else {
            throw NPError.documentIsReadOnly
        }
        let normalized = NPLineEndingManager.normalize(textContent, to: currentLineEnding)
        return try NPEncodingManager.shared.encode(normalized, as: currentEncoding, includeBOM: hasBOM)
    }

    // MARK: - 保存面板

    /// 配置保存面板：默认补 `.txt` 扩展名（PRD FR-009：首次保存默认 `*.txt`），
    /// 同时允许用户自改其他扩展名（对齐 Win11 行为）。
    /// - Parameter savePanel: 保存面板
    /// - Returns: 是否继续显示面板
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowedContentTypes = [.plainText]
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return super.prepareSavePanel(savePanel)
    }

    // MARK: - 窗口

    /// 窗口装配工厂注入点。
    ///
    /// 由 App 层在启动时注入（见 `AppDelegate.applicationWillFinishLaunching` 与 `NPTabWindowManager`），
    /// 以闭包注入消除 Document 层对 Editor/UI 层的逆向依赖（`08_KIMI_INSTRUCTION.md` §3）。
    /// 返回 `nil` 表示文档已由路由作为标签加入现有窗口，无需自建窗口控制器。
    static var windowControllerFactory: (@MainActor (NPTextDocument) -> NSWindowController?)?

    /// 创建文档窗口控制器（装配逻辑委托注入的工厂；多标签路由下可能作为标签加入现有窗口）。
    override func makeWindowControllers() {
        guard let windowController = Self.windowControllerFactory?(self) else {
            // 工厂未注入，或文档已被路由为现有窗口的标签：均不创建窗口控制器
            return
        }
        addWindowController(windowController)
    }
}
