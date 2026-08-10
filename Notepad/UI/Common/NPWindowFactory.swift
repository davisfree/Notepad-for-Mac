//
//  NPWindowFactory.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 文档窗口装配工厂（UI 层）。
///
/// 多标签架构（`01_TECH_SPEC.md` 3.4）：`makeTabEntry(for:)` 装配单个标签的全部内容
/// （编辑区 + 状态栏 + 查找栏接线）；`makeWindowController(for:)` 装配标签组窗口
/// （标签栏 + 内容容器 + 首个标签）。
/// `NPTextDocument` 通过闭包注入经 `NPTabWindowManager` 路由调用，避免 Document 层逆向依赖。
@MainActor
enum NPWindowFactory {

    // MARK: - 常量

    /// 默认窗口尺寸（`02_UI_DESIGN.md` 4.1：800 × 600）
    private static let defaultSize = NSSize(width: 800, height: 600)
    /// 最小窗口尺寸（`02_UI_DESIGN.md` 4.1：400 × 300）
    private static let minimumSize = NSSize(width: 400, height: 300)

    // MARK: - 标签装配

    /// 装配单个标签的全部内容（编辑器/状态栏/查找栏控制器 + 内容视图）。
    /// - Parameter document: 目标文档
    /// - Returns: 标签装配
    static func makeTabEntry(for document: NPTextDocument) -> NPTabBarController.TabEntry {
        let editorView = NPEditorView(frame: .zero)
        // 偏好默认值对新标签生效（PRD 7.1）
        let preferences = NPPreferences.shared
        editorView.isWordWrapEnabled = preferences.isWordWrapEnabled
        editorView.font = preferences.font
        editorView.zoomLevel = preferences.defaultZoomLevel

        let editorController = NPEditorController(editorView: editorView, document: document)
        let statusBarView = NPStatusBarView(frame: .zero)
        let statusBarController = NPStatusBarController(statusBar: statusBarView,
                                                        document: document,
                                                        editorView: editorView)
        // 行列/缩放回调：NPEditorController（Editor）经闭包转发，避免 Editor 层依赖 UI 层
        editorController.onCursorDidChange = { [weak statusBarController] line, column in
            statusBarController?.updateCursor(line: line, column: column)
        }
        editorController.onZoomDidChange = { [weak statusBarController] zoomLevel in
            statusBarController?.updateZoom(zoomLevel)
        }
        // 文本变化：状态栏字符数
        editorController.onTextDidChange = { [weak statusBarController] in
            statusBarController?.updateCharacterCount()
        }
        // 光标位置回报会话备份（Services 层，随文档弱引用）
        editorController.onCursorPositionChange = { [weak document] position in
            guard let document else {
                return
            }
            NPBackupService.shared.noteCursorPosition(position, for: document)
        }

        let findBarController = NPFindBarController(editorController: editorController,
                                                    editorView: editorView)
        let contentView = makeContentView(editorView: editorView, statusBar: statusBarView,
                                          findBar: findBarController.findBar)
        return NPTabBarController.TabEntry(
            identifier: UUID(),
            document: document,
            editorController: editorController,
            statusBarController: statusBarController,
            findBarController: findBarController,
            contentView: contentView
        )
    }

    // MARK: - 窗口装配

    /// 装配标签组窗口（含首个标签）。
    /// - Parameter document: 首个标签的文档
    /// - Returns: 标签组窗口控制器（未加入文档、未注册路由，由调用方处理）
    static func makeWindowController(for document: NPTextDocument) -> NPEditorWindowController {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = minimumSize
        let displayName: String = document.displayName ?? ""
        window.title = "\(displayName) - Notepad"
        window.contentView = NSView(frame: window.contentLayoutRect)

        let tabBarView = NPTabBarView(frame: .zero)
        let tabBarController = NPTabBarController(tabBar: tabBarView)
        tabBarController.makeEntry = { tabDocument in
            makeTabEntry(for: tabDocument)
        }
        let windowController = NPEditorWindowController(window: window,
                                                        tabBarController: tabBarController,
                                                        tabBarView: tabBarView)
        windowController.addTab(for: document)
        windowController.shouldCascadeWindows = true
        window.center()
        return windowController
    }

    // MARK: - 私有

    /// 装配查找栏 + 编辑区 + 状态栏的垂直布局（NSStackView 自动折叠隐藏的查找栏/状态栏，
    /// 查找栏在编辑区上方推动布局、不遮挡内容，状态栏高度严格 22pt）。
    /// - Parameters:
    ///   - editorView: 编辑器视图
    ///   - statusBar: 状态栏视图
    ///   - findBar: 查找栏视图（初始隐藏）
    /// - Returns: 标签内容视图
    private static func makeContentView(editorView: NPEditorView, statusBar: NPStatusBarView,
                                        findBar: NPFindBarView) -> NSView {
        let container = NSView(frame: .zero)
        findBar.isHidden = true
        let stack = NSStackView(views: [findBar, editorView, statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: NPStatusBarView.height)
        ])
        return container
    }
}
