//
//  NPTabBarController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 标签栏控制器（UI 层组合根，非契约类型）。
///
/// 业务协调：标签增删/排序/选择、关闭流程（未保存确认）、右键菜单五项、拖出窗口转发。
/// 文档与内容装配的映射（`TabEntry`）由本控制器持有；窗口切换等副作用经闭包回调（08 §3）。
@MainActor
final class NPTabBarController: NPTabBarDelegate {

    // MARK: - 类型

    /// 单个标签的全部装配（文档 + 各控制器 + 内容视图）。
    struct TabEntry {
        /// 标签标识
        let identifier: UUID
        /// 文档
        let document: NPTextDocument
        /// 编辑器控制器
        let editorController: NPEditorController
        /// 状态栏控制器
        let statusBarController: NPStatusBarController
        /// 查找栏控制器
        let findBarController: NPFindBarController
        /// 内容视图（编辑区 + 状态栏）
        let contentView: NSView
    }

    // MARK: - 属性

    /// 标签栏视图
    let tabBar: NPTabBarView

    /// 标签装配列表（与 tabBar.tabs 顺序一致）
    private(set) var entries: [TabEntry] = []

    /// 标签组模型（选中索引唯一来源）
    private var model = NPTabGroupModel()

    /// 标签组标识（会话归属元数据）
    let windowGroupID = UUID()

    /// 内容装配器（由 `NPWindowFactory` 注入）
    var makeEntry: ((NPTextDocument) -> TabEntry)?

    /// 选中变化回调（窗口控制器换内容视图与 document；nil 表示组已空）
    var onSelectionChange: ((TabEntry?) -> Void)?
    /// 最后一个标签关闭回调（窗口控制器决定关窗口）
    var onAllTabsClosed: (() -> Void)?
    /// 拖出窗口回调（App 层建新窗口托管该文档）
    var onDragOut: ((TabEntry) -> Void)?

    /// 关闭确认完成回调（按文档键控，支持批量顺序关闭）
    private var closeCompletions: [ObjectIdentifier: (Bool) -> Void] = [:]

    /// 状态栏隐藏状态（应用到全部标签，并对新标签生效）
    private var statusBarsHidden = false

    // MARK: - 初始化

    /// 创建控制器并接管标签栏委托。
    /// - Parameter tabBar: 标签栏视图
    init(tabBar: NPTabBarView) {
        self.tabBar = tabBar
        tabBar.delegate = self
    }

    // MARK: - 状态

    /// 当前选中装配
    var selectedEntry: TabEntry? {
        entries.indices.contains(model.selectedIndex) ? entries[model.selectedIndex] : nil
    }

    /// 标签数量
    var count: Int {
        entries.count
    }

    // MARK: - 标签管理

    /// 添加标签（装配内容、接入文档状态回调、注册会话备份、选中新标签）。
    /// - Parameter document: 文档
    func addTab(for document: NPTextDocument) {
        guard let makeEntry else {
            return
        }
        let entry = makeEntry(document)
        entries.append(entry)
        model.append(entry.identifier)
        wireDocumentCallbacks(entry)
        tabBar.addTab(makeTabItem(for: entry))
        entry.statusBarController.statusBar.isHidden = statusBarsHidden
        NPBackupService.shared.registerDocument(document)
        NPBackupService.shared.noteWindowContext(windowGroupID: windowGroupID,
                                                 tabIndex: entries.count - 1,
                                                 for: document)
        selectTab(at: model.selectedIndex)
    }

    /// 请求关闭标签（开关 ON 直接关闭——内容已在会话备份，01 §3.5；OFF 经 canClose 弹确认）。
    /// - Parameters:
    ///   - index: 标签索引
    ///   - completion: 完成回调（是否实际关闭）
    func requestCloseTab(at index: Int, completion: ((Bool) -> Void)? = nil) {
        guard entries.indices.contains(index) else {
            completion?(false)
            return
        }
        let document = entries[index].document
        // 未修改或空内容（含"输入后删光"）：与新建文档无异，直接关闭不提示
        guard document.isDocumentEdited, !document.textContent.isEmpty else {
            closeTabImmediately(at: index)
            completion?(true)
            return
        }
        // 直接关闭标签：有未保存内容时经系统确认弹窗（用户规则 1，对齐 Win11）
        if let completion {
            closeCompletions[ObjectIdentifier(document)] = completion
        }
        document.canClose(withDelegate: self,
                          shouldClose: #selector(document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
    }

    /// 顺序请求关闭全部标签（窗口/退出关闭流程；任一取消则中止）。
    /// - Parameter completion: 完成回调（全部关闭为 true，任一取消为 false）
    func requestCloseAllTabs(completion: ((Bool) -> Void)? = nil) {
        requestCloseTabs(at: Array(entries.indices.reversed())) { allClosed in
            completion?(allClosed)
        }
    }

    /// 设置全部标签的状态栏显隐（绑定 `NPPreferences.isStatusBarVisible`）。
    /// - Parameter hidden: 是否隐藏
    func setStatusBarsHidden(_ hidden: Bool) {
        statusBarsHidden = hidden
        for entry in entries {
            entry.statusBarController.statusBar.isHidden = hidden
        }
    }

    /// 选中下一个/上一个标签（⇧⌘] / ⇧⌘[，回绕）。
    /// - Parameter delta: 步进（+1 / -1）
    func stepSelection(by delta: Int) {
        guard !entries.isEmpty else {
            return
        }
        let next = (model.selectedIndex + delta + entries.count) % entries.count
        selectTab(at: next)
    }

    // MARK: - NPTabBarDelegate

    /// 选中标签。
    func tabBar(_ tabBar: NPTabBarView, didSelectTabAt index: Int) {
        selectTab(at: index)
    }

    /// 关闭标签（走未保存确认流程）。
    func tabBar(_ tabBar: NPTabBarView, didCloseTabAt index: Int) {
        requestCloseTab(at: index)
    }

    /// 拖拽排序完成：重排装配与模型，重建标签栏视图，并同步会话归属标签序。
    func tabBar(_ tabBar: NPTabBarView, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int) {
        guard entries.indices.contains(sourceIndex), entries.indices.contains(destinationIndex) else {
            return
        }
        let entry = entries.remove(at: sourceIndex)
        entries.insert(entry, at: destinationIndex)
        model.move(from: sourceIndex, to: destinationIndex)
        tabBar.reloadTabs(entries.map { entry in makeTabItem(for: entry) })
        tabBar.selectedIndex = model.selectedIndex
        for (index, entry) in entries.enumerated() {
            NPBackupService.shared.noteWindowContext(windowGroupID: windowGroupID,
                                                     tabIndex: index, for: entry.document)
        }
    }

    /// 拖出窗口：从本组摘除（不关闭文档），转发给 App 层建新窗口。
    func tabBar(_ tabBar: NPTabBarView, didDragOutTabAt index: Int) {
        guard entries.indices.contains(index) else {
            return
        }
        let entry = entries[index]
        removeTab(at: index)
        onDragOut?(entry)
    }

    /// 右键菜单（关闭 / 关闭其他 / 关闭右侧 / 复制标签 / 在 Finder 中显示，PRD FR-002）。
    func tabBar(_ tabBar: NPTabBarView, didRequestContextMenuForTabAt index: Int) -> NSMenu? {
        let menu = NSMenu()
        addMenuItem(to: menu, titleKey: "Tab.Context.Close", action: #selector(closeTabAction(_:)), index: index)
        addMenuItem(to: menu, titleKey: "Tab.Context.CloseOthers",
                    action: #selector(closeOtherTabsAction(_:)), index: index)
        addMenuItem(to: menu, titleKey: "Tab.Context.CloseToRight",
                    action: #selector(closeTabsToRightAction(_:)), index: index)
        addMenuItem(to: menu, titleKey: "Tab.Context.Duplicate",
                    action: #selector(duplicateTabAction(_:)), index: index)
        let revealItem = addMenuItem(to: menu, titleKey: "Tab.Context.RevealInFinder",
                                     action: #selector(revealInFinderAction(_:)), index: index)
        revealItem.isEnabled = entries.indices.contains(index) && entries[index].document.fileURL != nil
        return menu
    }

    // MARK: - 菜单动作

    /// 创建菜单项（representedObject 为标签索引）。
    /// - Returns: 菜单项
    @discardableResult
    private func addMenuItem(to menu: NSMenu, titleKey: String, action: Selector, index: Int) -> NSMenuItem {
        let item = NSMenuItem(title: NSLocalizedString(titleKey, comment: "标签右键菜单"),
                              action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: index)
        menu.addItem(item)
        return item
    }

    /// 关闭。
    /// - Parameter sender: 菜单项
    @objc private func closeTabAction(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue else {
            return
        }
        requestCloseTab(at: index)
    }

    /// 关闭其他标签页。
    /// - Parameter sender: 菜单项
    @objc private func closeOtherTabsAction(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue else {
            return
        }
        let indices = entries.indices.filter { $0 != index }.reversed()
        requestCloseTabs(at: Array(indices)) { _ in }
    }

    /// 关闭右侧标签页。
    /// - Parameter sender: 菜单项
    @objc private func closeTabsToRightAction(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue else {
            return
        }
        let indices = entries.indices.filter { $0 > index }.reversed()
        requestCloseTabs(at: Array(indices)) { _ in }
    }

    /// 复制标签页（新建无标题文档并拷贝内容，标记为未保存）。
    /// - Parameter sender: 菜单项
    @objc private func duplicateTabAction(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue,
              entries.indices.contains(index) else {
            return
        }
        do {
            let source = entries[index].document
            guard let duplicate = try NSDocumentController.shared.makeUntitledDocument(
                ofType: "public.plain-text") as? NPTextDocument else {
                return
            }
            duplicate.textContent = source.textContent
            duplicate.updateChangeCount(.changeDone)
            addTab(for: duplicate)
        } catch {
            // 创建失败：无恢复路径，静默放弃（NSDocumentController 已记录错误）
        }
    }

    /// 在 Finder 中显示。
    /// - Parameter sender: 菜单项
    @objc private func revealInFinderAction(_ sender: NSMenuItem) {
        guard let index = (sender.representedObject as? NSNumber)?.intValue,
              entries.indices.contains(index),
              let url = entries[index].document.fileURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 关闭流程

    /// `NSDocument.canClose` 回调：确认后关闭文档并移除标签。
    /// - Parameters:
    ///   - document: 文档
    ///   - shouldClose: 是否关闭
    ///   - contextInfo: 上下文（未使用）
    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let key = ObjectIdentifier(document)
        defer {
            closeCompletions.removeValue(forKey: key)?(shouldClose)
        }
        guard shouldClose, let index = entries.firstIndex(where: { $0.document === document }) else {
            return
        }
        closeTabImmediately(at: index)
    }

    /// 顺序关闭指定索引的标签（任一取消则中止后续）。
    /// - Parameters:
    ///   - indices: 标签索引（按关闭顺序）
    ///   - completion: 完成回调（全部关闭为 true，任一取消为 false）
    private func requestCloseTabs(at indices: [Int], completion: @escaping (Bool) -> Void) {
        guard let first = indices.first else {
            completion(true)
            return
        }
        requestCloseTab(at: first) { [weak self] closed in
            guard closed else {
                completion(false)
                return
            }
            self?.requestCloseTabs(at: Array(indices.dropFirst()), completion: completion)
        }
    }

    /// 关闭文档并移除标签（直接关闭标签路径；系统确认流程已结束）；同步删除会话备份。
    ///
    /// 不补写盘：用户在确认弹窗中已做出选择（"保存"由系统流程完成，"不保存"即丢弃）。
    /// - Parameter index: 标签索引
    /// - Note: 关闭前必须先把文档从共享窗口控制器上注销——
    ///   `NSDocument.close()` 会连带关闭其 `windowControllers` 的窗口，
    ///   否则关闭当前选中标签会把还有其他标签的窗口一起关掉
    private func closeTabImmediately(at index: Int) {
        guard entries.indices.contains(index) else {
            return
        }
        let document = entries[index].document
        for windowController in document.windowControllers {
            document.removeWindowController(windowController)
        }
        NPBackupService.shared.unregisterDocument(document)
        // 清脏避免 NSDocument.close() 对脏文档触发系统"保留文稿"对话框（探针实测）
        document.updateChangeCount(.changeCleared)
        document.close()
        removeTab(at: index)
    }

    /// 关窗摘除全部标签（不关闭文档、不弹确认、保留备份与内存中的文档）。
    ///
    /// 用户规则 2 的完整语义：关窗后文档仍留在内存（Dock  reopen 时原样重建窗口），
    /// 备份保留在磁盘（下次启动会话恢复）；脏状态保留以便重开时恢复圆点标记。
    func detachAllTabsForWindowClose() {
        for entry in entries {
            let document = entry.document
            // 尾缘窗口内的编辑先落盘（备份始终写；原文件写回仅自动保存 ON）
            NPBackupService.shared.flushPendingWrites(for: document)
            for windowController in document.windowControllers {
                document.removeWindowController(windowController)
            }
            NPBackupService.shared.detachDocumentPreservingBackup(document)
        }
        entries.removeAll()
        model.removeAll()
        tabBar.reloadTabs([])
        onSelectionChange?(nil)
    }

    /// 移除标签（不关闭文档；用于拖出窗口）。
    /// - Parameter index: 标签索引
    private func removeTab(at index: Int) {
        guard entries.indices.contains(index) else {
            return
        }
        entries.remove(at: index)
        model.remove(at: index)
        tabBar.removeTab(at: index)
        if entries.isEmpty {
            onSelectionChange?(nil)
            onAllTabsClosed?()
        } else {
            onSelectionChange?(selectedEntry)
        }
    }

    // MARK: - 私有

    /// 选中标签并通知窗口控制器。
    /// - Parameter index: 标签索引
    private func selectTab(at index: Int) {
        model.select(index)
        tabBar.selectedIndex = model.selectedIndex
        onSelectionChange?(selectedEntry)
    }

    /// 由装配生成标签项数据。
    /// - Parameter entry: 标签装配
    /// - Returns: 标签项
    private func makeTabItem(for entry: TabEntry) -> NPTabItem {
        let displayName: String = entry.document.displayName ?? ""
        return NPTabItem(identifier: entry.identifier, title: displayName,
                         fileURL: entry.document.fileURL,
                         isModified: entry.document.isDocumentEdited)
    }

    /// 接入文档状态回调（标题与未保存圆点同步）。
    /// - Parameter entry: 标签装配
    private func wireDocumentCallbacks(_ entry: TabEntry) {
        entry.document.onDisplayNameChange = { [weak self, weak document = entry.document] in
            guard let self, let document,
                  let index = entries.firstIndex(where: { $0.document === document }) else {
                return
            }
            tabBar.updateTabTitle(at: index, title: document.displayName ?? "")
        }
        entry.document.onEditedStateChange = { [weak self, weak document = entry.document] isEdited in
            guard let self, let document,
                  let index = entries.firstIndex(where: { $0.document === document }) else {
                return
            }
            tabBar.updateTab(at: index, isModified: isEdited)
        }
    }
}
