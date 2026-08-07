//
//  NPTabWindowManager.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 标签窗口路由管理器（UI 层组合根，非契约类型）。
///
/// 决定文档进入现有窗口（作为新标签）还是新建窗口（对齐 Win11 行为）：
/// - 打开文件/新建标签：当前有窗口则插入为标签，无窗口则新窗口；
/// - 新建窗口（⌘N）：`preferExistingWindow` 临时置 `false` 强制新窗口；
/// - 拖出标签：摘除后由 `openInNewWindow` 托管为新窗口。
@MainActor
final class NPTabWindowManager {

    // MARK: - 单例

    static let shared = NPTabWindowManager()

    // MARK: - 属性

    /// 路由决策：系统文档流（打开/新建）优先进入当前窗口作为标签
    var preferExistingWindow = true

    /// 已登记的标签组窗口控制器（只读暴露，退出流程遍历用）
    private(set) var windowControllers: [NPEditorWindowController] = []

    // MARK: - 初始化

    private init() {}

    // MARK: - 路由

    /// 窗口工厂入口（`NPTextDocument.windowControllerFactory` 注入目标）。
    /// - Parameter document: 文档
    /// - Returns: 新窗口控制器；若文档已作为标签加入现有窗口则返回 `nil`
    func acquireWindowController(for document: NPTextDocument) -> NSWindowController? {
        if preferExistingWindow, let current = currentWindowController() {
            current.addTab(for: document)
            current.window?.makeKeyAndOrderFront(nil)
            return nil
        }
        let windowController = NPWindowFactory.makeWindowController(for: document)
        register(windowController)
        return windowController
    }

    /// 新建文档入口（⌘T）：当前窗口加标签，无窗口则新窗口。
    /// - Parameter document: 文档（已注册到 `NSDocumentController`，未经 `makeWindowControllers`）
    func addDocumentAsTabOrNewWindow(_ document: NPTextDocument) {
        if let current = currentWindowController() {
            current.addTab(for: document)
            current.window?.makeKeyAndOrderFront(nil)
            return
        }
        openInNewWindow(document)
    }

    /// 在新窗口中托管文档（拖出标签 / 无窗口时新建 / 会话恢复分组）。
    /// - Parameter document: 文档
    /// - Returns: 新窗口控制器
    @discardableResult
    func openInNewWindow(_ document: NPTextDocument) -> NPEditorWindowController {
        let windowController = NPWindowFactory.makeWindowController(for: document)
        document.addWindowController(windowController)
        register(windowController)
        windowController.showWindow(nil)
        return windowController
    }

    // MARK: - 登记

    /// 登记窗口控制器。
    /// - Parameter windowController: 标签组窗口控制器
    func register(_ windowController: NPEditorWindowController) {
        guard !windowControllers.contains(where: { $0 === windowController }) else {
            return
        }
        windowControllers.append(windowController)
    }

    /// 注销窗口控制器（窗口关闭时调用）。
    /// - Parameter windowController: 标签组窗口控制器
    func unregister(_ windowController: NPEditorWindowController) {
        windowControllers.removeAll { controller in
            controller === windowController
        }
    }

    // MARK: - 私有

    /// 当前活跃的标签组窗口控制器（优先 key/main 窗口，否则最近登记）。
    /// - Returns: 窗口控制器
    private func currentWindowController() -> NPEditorWindowController? {
        for window in [NSApp.keyWindow, NSApp.mainWindow] {
            if let controller = window?.windowController as? NPEditorWindowController {
                return controller
            }
        }
        return windowControllers.last
    }
}
