//
//  NPEditorWindowController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import Combine

/// 文档窗口控制器（标签组容器）。
///
/// 一个窗口聚合多个 `NPTextDocument`（`01_TECH_SPEC.md` 3.4）：持有 `NPTabBarController`，
/// 内容区显示当前选中标签的内容视图；切换标签即换视图 + `document` 指向当前文档
/// （保证保存面板/关闭确认/响应链 action 指向正确文档）。
/// 窗口标题为 `当前文档 displayName - Notepad`（PRD FR-012）。
@MainActor
final class NPEditorWindowController: NSWindowController {

    // MARK: - 属性

    /// 标签栏控制器（强引用持有）
    let tabBarController: NPTabBarController

    /// 标签栏视图
    private let tabBarView: NPTabBarView

    /// 内容容器（承载当前标签的内容视图）
    private let contentContainer = NSView()

    /// 当前展示的标签标识（避免重复换视图）
    private var shownEntryID: UUID?

    /// 窗口关闭流程进行中（避免 onAllTabsClosed 重入关窗）
    private var isClosingAllTabs = false

    /// Combine 订阅令牌（状态栏可见性绑定）
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - 初始化

    /// 以窗口与标签栏控制器创建窗口控制器。
    /// - Parameters:
    ///   - window: 文档窗口
    ///   - tabBarController: 标签栏控制器
    ///   - tabBarView: 标签栏视图
    init(window: NSWindow, tabBarController: NPTabBarController, tabBarView: NPTabBarView) {
        self.tabBarController = tabBarController
        self.tabBarView = tabBarView
        super.init(window: window)
        window.delegate = self
        // 红色关闭按钮改走自定义动作：系统 performClose 对脏文档窗口会先弹确认
        // （探针实测，委托均被抢占），用户规则 2 要求关窗静默，必须在入口层拦截
        window.standardWindowButton(.closeButton)?.target = self
        window.standardWindowButton(.closeButton)?.action = #selector(closeWindowAction(_:))
        layoutViews()
        wireTabBarController()
        bindStatusBarVisibility()
        installTouchBar()
    }

    /// 不支持归档恢复（窗口由 `NPWindowFactory` 代码装配）。
    /// - Parameter coder: 解码器
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NPEditorWindowController 不支持 coder 初始化，请使用 init(window:tabBarController:tabBarView:)")
    }

    // MARK: - 标签管理

    /// 添加标签（⌘T / 打开文件路由经此进入当前窗口）；大文件只读模式提示并禁用编辑。
    /// - Parameter document: 文档
    func addTab(for document: NPTextDocument) {
        tabBarController.addTab(for: document)
        guard document.isReadOnly else {
            return
        }
        if let entry = tabBarController.entries.last, entry.document === document {
            entry.editorController.editorView.isEditable = false
        }
        presentLargeFileAlert()
    }

    /// 大文件只读提示（PRD FR-001：>10MB 提示并以只读模式打开）。
    private func presentLargeFileAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("LargeFile.ReadOnlyTitle", comment: "大文件只读提示：标题")
        alert.informativeText = NSLocalizedString("LargeFile.ReadOnlyMessage", comment: "大文件只读提示：内容")
        alert.alertStyle = .informational
        guard let window else {
            return
        }
        alert.beginSheetModal(for: window) { _ in }
    }

    /// 关闭当前标签（⌘W；最后一个标签关闭后窗口随之关闭）。
    /// - Parameter sender: 菜单项
    @objc func closeCurrentTab(_ sender: Any?) {
        guard let selectedEntry = tabBarController.selectedEntry,
              let index = tabBarController.entries.firstIndex(where: { $0.identifier == selectedEntry.identifier }) else {
            return
        }
        tabBarController.requestCloseTab(at: index)
    }

    /// 文件 → 关闭窗口（⇧⌘W）与红色关闭按钮：静默摘除全部标签后关窗
    /// （用户规则 2——关窗不提示，内容留在会话备份与内存文档中，重开/重启恢复）。
    /// - Parameter sender: 菜单项或关闭按钮
    /// - Note: 使用自定义 action 而非标准 `performClose:`——macOS 26 会为标准 selector
    ///   的菜单项自动配 SF Symbols 图标；且 `performClose` 对脏文档窗口会先弹确认
    @objc func closeWindowAction(_ sender: Any?) {
        guard let window else {
            return
        }
        isClosingAllTabs = true
        tabBarController.detachAllTabsForWindowClose()
        isClosingAllTabs = false
        window.close()
    }

    /// 选中下一个标签（⇧⌘]）。
    /// - Parameter sender: 菜单项
    @objc func selectNextTab(_ sender: Any?) {
        tabBarController.stepSelection(by: 1)
    }

    /// 选中上一个标签（⇧⌘[）。
    /// - Parameter sender: 菜单项
    @objc func selectPreviousTab(_ sender: Any?) {
        tabBarController.stepSelection(by: -1)
    }

    // MARK: - 窗口标题

    /// 同步窗口标题为 `当前文档 displayName - Notepad`。
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if NPPreferences.shared.isAutoSaveEnabled {
            // 自动保存 ON：脏状态由会话备份承载（01 §3.5），窗口不呈现"已编辑"标记，
            // 避免系统依据 window.isDocumentEdited 在关窗时弹出保存确认
            // （未保存状态已由标签页圆点表达，PRD FR-002）
            window?.isDocumentEdited = false
        }
        guard let document else {
            return
        }
        let displayName: String = document.displayName ?? ""
        window?.title = "\(displayName) - Notepad"
    }

    // MARK: - 私有：布局

    /// 装配标签栏 + 内容容器的垂直布局。
    private func layoutViews() {
        guard let contentView = window?.contentView else {
            return
        }
        let stack = NSStackView(views: [tabBarView, contentContainer])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: NPTabBarView.height),
        ])
    }

    // MARK: - 私有：接线

    /// 接线标签栏控制器回调。
    private func wireTabBarController() {
        tabBarController.onSelectionChange = { [weak self] entry in
            self?.showEntry(entry)
        }
        tabBarController.onAllTabsClosed = { [weak self] in
            guard let self, !isClosingAllTabs else {
                return
            }
            window?.close()
        }
        tabBarController.onDragOut = { entry in
            NPTabWindowManager.shared.openInNewWindow(entry.document)
        }
    }

    /// 切换展示的标签（换内容视图、document 指向、窗口标题）。
    /// - Parameter entry: 目标标签装配（nil 清空）
    private func showEntry(_ entry: NPTabBarController.TabEntry?) {
        guard entry?.identifier != shownEntryID else {
            return
        }
        shownEntryID = entry?.identifier
        for subview in contentContainer.subviews {
            subview.removeFromSuperview()
        }
        if let entry {
            let view = entry.contentView
            view.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            ])
        }
        // document 指向当前标签文档：保存面板/关闭确认/响应链 action 随之指向正确文档。
        // 注意：必须经 addWindowController / removeWindowController 注册——
        // 直接给 document 属性赋值不会更新 NSDocument.windowControllers，
        // 且会使后续 addWindowController 变为 no-op（探针实测），
        // 导致 showWindows 无窗口控制器可显示（冷启动窗口不出现）
        if document !== entry?.document {
            if let oldDocument = document {
                oldDocument.removeWindowController(self)
            }
            if let newDocument = entry?.document {
                newDocument.addWindowController(self)
            }
        }
        synchronizeWindowTitleWithDocumentName()
    }

    /// 绑定状态栏可见性偏好（应用到全部标签）。
    private func bindStatusBarVisibility() {
        NPPreferences.shared.$isStatusBarVisible
            .sink { [weak self] isVisible in
                self?.tabBarController.setStatusBarsHidden(!isVisible)
            }
            .store(in: &cancellables)
    }
}

// MARK: - NSWindowDelegate

extension NPEditorWindowController: NSWindowDelegate {    /// 窗口关闭兜底（系统直接 `window.close()` 的路径，如退出流程）：
    /// 静默摘除全部标签，文档与备份保留（用户规则 2）。
    /// - Parameter sender: 窗口
    /// - Returns: 是否允许立即关闭
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard tabBarController.count > 0, !isClosingAllTabs else {
            return true
        }
        isClosingAllTabs = true
        tabBarController.detachAllTabsForWindowClose()
        isClosingAllTabs = false
        return true
    }

    /// 窗口关闭后注销路由登记。
    /// - Parameter notification: 关闭通知
    func windowWillClose(_ notification: Notification) {
        NPTabWindowManager.shared.unregister(self)
    }
}
