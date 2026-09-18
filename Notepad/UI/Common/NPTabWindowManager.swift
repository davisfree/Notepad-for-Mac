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
///   **新增标签一律落在最左端**（用户偏好，内部走 `insertTab(0)`）——包括 ⌘N 新建标签页、
///   快捷指令新建文档、打开文件（AppKit 工厂路径 `acquireWindowController`）；
///   仅会话恢复与 Dock 重开重建走 `.trailing` 以保持原有标签序；
/// - 新建窗口（⌘N）：`preferExistingWindow` 临时置 `false` 强制新窗口；
/// - 拖出标签：摘除后由 `openInNewWindow` 托管为新窗口。
@MainActor
final class NPTabWindowManager {

    // MARK: - 单例

    static let shared = NPTabWindowManager()

    // MARK: - 属性

    /// 路由决策：系统文档流（打开/新建）优先进入当前窗口作为标签
    var preferExistingWindow = true

    /// 新建文档的创建器（由 App 层注入）：`AppDelegate` 负责"创建无标题文档并补登记
    /// `NSDocumentController`"，此处只调用；未注入时"新建标签页"静默不做。
    /// 以闭包注入而非直接引用 App 层类型，保持依赖方向不变。
    var makeNewDocument: (() -> NPTextDocument?)?

    /// 已登记的标签组窗口控制器（只读暴露，退出流程遍历用）
    private(set) var windowControllers: [NPEditorWindowController] = []

    /// 最近一次成为 key 的标签组窗口（菜单跟踪期间 `NSApp.keyWindow`/`mainWindow` 均为 nil，
    /// 这份记忆是解析"当前文档"的依据；弱引用避免滞留已关窗口）
    private weak var lastActiveWindowController: NPEditorWindowController?

    /// 各登记窗口的 `didBecomeKey` 观察者（按窗口控制器标识键控，注销时移除）
    private var keyObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    // MARK: - 初始化

    private init() {}

    // MARK: - 路由

    /// 窗口工厂入口（`NPTextDocument.windowControllerFactory` 注入目标）。
    ///
    /// AppKit 展示文档时经此进入（`NSDocument.makeWindowControllers`：打开文件、打开最近使用、
    /// 拖文件到 Dock 图标等）：**新增标签一律落在最左端**（`insertTab(0)`），与 ⌘N 新建标签页一致。
    /// - Parameter document: 文档
    /// - Returns: 新窗口控制器；若文档已作为标签加入现有窗口则返回 `nil`
    func acquireWindowController(for document: NPTextDocument) -> NSWindowController? {
        if preferExistingWindow, let current = activeWindowController() {
            current.addTab(for: document, position: .leading)
            current.window?.makeKeyAndOrderFront(nil)
            return nil
        }
        let windowController = NPWindowFactory.makeWindowController(for: document)
        register(windowController)
        return windowController
    }

    /// 新建文档入口（⌘N 新建标签页 / 快捷指令"新建文档"）：**固定插入当前窗口标签组的最左端**。
    /// - Parameter document: 文档
    func openNewDocument(_ document: NPTextDocument) {
        addDocumentAsTabOrNewWindow(document, position: .leading)
    }

    /// 新建标签页（菜单"文件 → 新建标签页 ⌘N"与标签栏右端"+"按钮共用）：
    /// 经注入的 `makeNewDocument` 创建无标题文档，再插入当前窗口标签组最左端（无窗口则新建窗口）。
    func createNewDocumentAsTabOrNewWindow() {
        guard let document = makeNewDocument?() else {
            return
        }
        openNewDocument(document)
    }

    /// 新建/重建文档入口：当前窗口加标签，无窗口则新窗口。
    /// - Parameters:
    ///   - document: 文档（已注册到 `NSDocumentController`，未经 `makeWindowControllers`）
    ///   - position: 标签插入位置。新建文档走 `openNewDocument(_:)`（固定 `.leading`）；
    ///     Dock 重开重建已有关窗文档传 `.trailing` 以保持原有顺序
    func addDocumentAsTabOrNewWindow(_ document: NPTextDocument,
                                     position: NPTabBarController.InsertionPosition) {
        if let current = activeWindowController() {
            current.addTab(for: document, position: position)
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
        observeKeyWindow(windowController)
    }

    /// 注销窗口控制器（窗口关闭时调用）。
    /// - Parameter windowController: 标签组窗口控制器
    func unregister(_ windowController: NPEditorWindowController) {
        if let observer = keyObservers.removeValue(forKey: ObjectIdentifier(windowController)) {
            NotificationCenter.default.removeObserver(observer)
        }
        if lastActiveWindowController === windowController {
            lastActiveWindowController = nil
        }
        windowControllers.removeAll { controller in
            controller === windowController
        }
    }

    /// 记录最近成为 key 的标签组窗口。
    ///
    /// 菜单校验发生在菜单跟踪期间，此时 `NSApp.keyWindow` 与 `NSApp.mainWindow` 均为 `nil`，
    /// 必须靠这份记忆解析当前文档；否则会退化成"最近登记的窗口"（通常是最后新建的窗口），
    /// 导致其它窗口的保存/另存为/打印恒变灰。
    /// - Parameter windowController: 目标窗口控制器
    func noteActive(_ windowController: NPEditorWindowController) {
        lastActiveWindowController = windowController
    }

    // MARK: - 私有

    /// 观察窗口成为 key 的时机，用于维护"最近活跃窗口"记忆。
    /// - Parameter windowController: 标签组窗口控制器
    private func observeKeyWindow(_ windowController: NPEditorWindowController) {
        guard let window = windowController.window else {
            return
        }
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self, weak windowController] _ in
            guard let windowController else {
                return
            }
            self?.noteActive(windowController)
        }
        keyObservers[ObjectIdentifier(windowController)] = observer
    }

    // MARK: - 活跃窗口解析

    /// 当前活跃的标签组窗口控制器（窗口路由与菜单校验的唯一事实来源）。
    ///
    /// 解析顺序：`key` → `main` → 最近活跃过的可见标签组窗口 → 最近登记的可见标签组窗口。
    /// 后两级回退不可省略：`NSApp.keyWindow` / `NSApp.mainWindow` 在 App 非激活、被面板抢占、
    /// 菜单跟踪期间均可能为 `nil`，而保存/另存为/打印/始终在最前都依赖"当前窗口"解析——
    /// 一旦返回 `nil`，菜单项会集体变灰且对应动作静默失效（`AppDelegate.validateMenuItem`）。
    /// - Returns: 窗口控制器（无任何标签组窗口时为 `nil`）
    func activeWindowController() -> NPEditorWindowController? {
        for window in [NSApp.keyWindow, NSApp.mainWindow] {
            if let controller = window?.windowController as? NPEditorWindowController {
                lastActiveWindowController = controller
                return controller
            }
        }
        if let last = lastActiveWindowController,
           last.window?.isVisible == true,
           windowControllers.contains(where: { $0 === last }) {
            return last
        }
        return windowControllers.last { $0.window?.isVisible == true } ?? windowControllers.last
    }
}
