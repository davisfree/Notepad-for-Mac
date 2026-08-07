//
//  NPStatusBarController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 状态栏控制器（UI 层内部装配类，非契约类型）。
///
/// 实现 `NPStatusBarDelegate`：点击弹出缩放/换行符/编码菜单（回写文档与编辑器）；
/// 订阅文档编码/换行符变更通知刷新显示；行列/缩放由 `NPEditorController` 闭包回调驱动。
@MainActor
final class NPStatusBarController: NPStatusBarDelegate {

    // MARK: - 常量

    /// 缩放预设（PRD 4.3：100% / 125% / 150% / 200% / 自定义）
    private static let zoomPresets: [(title: String, value: Double)] = [
        ("100%", 1.0),
        ("125%", 1.25),
        ("150%", 1.5),
        ("200%", 2.0),
    ]

    /// 缩放预设匹配容差（浮点比较）
    private static let zoomMatchTolerance = 0.001

    // MARK: - 属性

    /// 状态栏视图
    let statusBar: NPStatusBarView

    /// 关联文档（弱引用，生命周期由 NSDocumentController 管理）
    private weak var document: NPTextDocument?
    /// 关联编辑器视图（弱引用，随窗口存在）
    private weak var editorView: NPEditorView?

    /// 通知观察者令牌（deinit 移除）
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - 初始化

    /// 创建控制器：接管状态栏委托、读取文档初始值、订阅文档通知。
    /// - Parameters:
    ///   - statusBar: 状态栏视图
    ///   - document: 关联文档
    ///   - editorView: 关联编辑器视图
    init(statusBar: NPStatusBarView, document: NPTextDocument, editorView: NPEditorView) {
        self.statusBar = statusBar
        self.document = document
        self.editorView = editorView
        statusBar.delegate = self
        refreshFromDocument()
        let center = NotificationCenter.default
        for name in [NPNotificationNames.documentEncodingDidChange, NPNotificationNames.documentLineEndingDidChange] {
            let observer = center.addObserver(forName: name, object: document, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshFromDocument()
                }
            }
            notificationObservers.append(observer)
        }
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 显示更新（由 NPEditorController 闭包回调驱动）

    /// 更新光标行列显示。
    /// - Parameters:
    ///   - line: 行号（从 1 开始）
    ///   - column: 列号（从 1 开始）
    func updateCursor(line: Int, column: Int) {
        statusBar.lineNumber = line
        statusBar.columnNumber = column
    }

    /// 更新缩放显示。
    /// - Parameter zoomLevel: 缩放比例（1.0 = 100%）
    func updateZoom(_ zoomLevel: Double) {
        statusBar.zoomLevel = zoomLevel
    }

    // MARK: - NPStatusBarDelegate

    /// 点击 "Ln, Col"：弹出"转到行"浮动面板（复用编辑器 ⌃G 入口）。
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapLineColumn(_ statusBar: NPStatusBarView) {
        editorView?.goToLineAction(nil)
    }

    /// 点击缩放：弹出缩放选择菜单（100% / 125% / 150% / 200% / 自定义，PRD 4.3）。
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapZoomLevel(_ statusBar: NPStatusBarView) {
        let menu = NSMenu()
        for preset in Self.zoomPresets {
            let item = NSMenuItem(title: preset.title, action: #selector(selectZoom(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: preset.value)
            if let zoomLevel = editorView?.zoomLevel, abs(zoomLevel - preset.value) < Self.zoomMatchTolerance {
                item.state = .on
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let customItem = NSMenuItem(
            title: NSLocalizedString("StatusBar.Zoom.Custom", comment: "状态栏：自定义缩放"),
            action: #selector(selectCustomZoom(_:)),
            keyEquivalent: ""
        )
        customItem.target = self
        menu.addItem(customItem)
        presentMenu(menu)
    }

    /// 点击换行符：弹出 CRLF / LF / CR 切换菜单（回写 `document.changeLineEnding`）。
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapLineEnding(_ statusBar: NPStatusBarView) {
        let menu = NSMenu()
        for lineEnding in NPLineEnding.allCases {
            let item = NSMenuItem(title: lineEnding.displayName, action: #selector(selectLineEnding(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = lineEnding.rawValue
            if lineEnding == document?.currentLineEnding {
                item.state = .on
            }
            menu.addItem(item)
        }
        presentMenu(menu)
    }

    /// 点击编码：弹出编码切换菜单（回写 `document.changeEncoding`，失败弹错）。
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapEncoding(_ statusBar: NPStatusBarView) {
        let menu = NSMenu()
        for encoding in NPEncodingManager.supportedEncodings {
            let item = NSMenuItem(
                title: NPStatusBarFormatter.encodingName(for: encoding, hasBOM: false),
                action: #selector(selectEncoding(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: encoding.rawValue)
            if encoding == document?.currentEncoding {
                item.state = .on
            }
            menu.addItem(item)
        }
        presentMenu(menu)
    }

    // MARK: - 菜单动作

    /// 选择缩放预设。
    /// - Parameter sender: 菜单项（representedObject 为 Double）
    @objc private func selectZoom(_ sender: NSMenuItem) {
        guard let value = (sender.representedObject as? NSNumber)?.doubleValue else {
            return
        }
        editorView?.zoomLevel = value
    }

    /// 自定义缩放（占位）。
    /// - Parameter sender: 菜单项
    @objc private func selectCustomZoom(_ sender: NSMenuItem) {
        // TODO: 自定义缩放输入对话框（后续迭代；当前可用 ⌘+/⌘- 以 10% 步进）
    }

    /// 选择换行符格式。
    /// - Parameter sender: 菜单项（representedObject 为 NPLineEnding.rawValue）
    @objc private func selectLineEnding(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lineEnding = NPLineEnding(rawValue: raw) else {
            return
        }
        document?.changeLineEnding(to: lineEnding)
    }

    /// 选择编码（转换失败时弹出错误提示）。
    /// - Parameter sender: 菜单项（representedObject 为编码 rawValue）
    @objc private func selectEncoding(_ sender: NSMenuItem) {
        guard let raw = (sender.representedObject as? NSNumber)?.uintValue else {
            return
        }
        do {
            try document?.changeEncoding(to: String.Encoding(rawValue: raw))
        } catch {
            presentEncodingError()
        }
    }

    // MARK: - 私有

    /// 从文档刷新编码/换行符显示（初始值与通知驱动）。
    private func refreshFromDocument() {
        guard let document else {
            return
        }
        statusBar.encoding = document.currentEncoding
        statusBar.encodingHasBOM = document.hasBOM
        statusBar.lineEnding = document.currentLineEnding
    }

    /// 在状态栏上方弹出菜单。
    /// - Parameter menu: 菜单
    private func presentMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: statusBar.bounds.height), in: statusBar)
    }

    /// 编码转换失败错误提示（sheet）。
    private func presentEncodingError() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Error.Encoding.ConversionFailed",
                                              comment: "编码转换失败提示")
        alert.alertStyle = .warning
        guard let window = statusBar.window else {
            return
        }
        alert.beginSheetModal(for: window) { _ in }
    }
}
