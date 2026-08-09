//
//  NPPreferencesWindowController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-08.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 偏好设置窗口控制器（App 菜单"设置…"⌘, 入口）。
///
/// 目录式布局（对齐 macOS 系统设置）：左侧 source list 目录（通用 / 编辑器），
/// 右侧为选中页内容；内容区底部右侧为"全部恢复默认"按钮。
/// 窗口由 `AppDelegate` 懒创建并持有，关闭仅隐藏（`isReleasedWhenClosed = false`）。
@MainActor
final class NPPreferencesWindowController: NSWindowController {

    // MARK: - 目录页

    /// 目录条目（左侧 source list 行）
    private enum Page: Int, CaseIterable {
        case general
        case editor

        /// 目录显示名
        var title: String {
            switch self {
            case .general:
                return NSLocalizedString("Preferences.General", tableName: "Preferences",
                                         comment: "偏好设置：通用目录项")
            case .editor:
                return NSLocalizedString("Preferences.Editor", tableName: "Preferences",
                                         comment: "偏好设置：编辑器目录项")
            }
        }

        /// 目录图标（SF Symbol）
        var symbolName: String {
            switch self {
            case .general:
                return "gearshape"
            case .editor:
                return "textformat"
            }
        }
    }

    // MARK: - 依赖

    /// 偏好存储
    private let preferences: NPPreferences

    // MARK: - 私有

    /// 分栏控制器（左侧目录 + 右侧内容）
    private let splitViewController = NSSplitViewController()
    /// 目录列表（source list 样式）
    private let sidebarTableView = NSTableView()
    /// 右侧内容容器（当前页视图 + 底部"全部恢复默认"）
    private let detailContainerView = NSView(frame: .zero)
    /// 各页内容视图控制器（懒创建并缓存，保留页面状态）
    private lazy var pageViewControllers: [Page: NSViewController] = [:]
    /// 当前显示的页
    private var currentPage: Page?
    /// "全部恢复默认"按钮（位于内容区底部，换页时保留不重建；`assembleContent` 中创建）
    private var resetButton: NSButton!

    // MARK: - 初始化

    /// 创建偏好设置窗口。
    /// - Parameter preferences: 偏好存储（默认单例）
    init(preferences: NPPreferences = .shared) {
        self.preferences = preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 320)
        super.init(window: window)
        window.title = NSLocalizedString("Preferences.Title", tableName: "Preferences",
                                         comment: "偏好设置窗口标题")
        assembleContent()
        show(page: .general)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("本工程不使用 nib/storyboard（纯代码布局）")
    }

    // MARK: - 动作

    /// "全部恢复默认"：确认后重置全部偏好（控件经 `preferencesDidChange` 通知自动回刷）。
    /// - Parameter sender: 按钮
    @objc private func resetAllPreferences(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Preferences.ResetAll.Confirm.Title",
                                              tableName: "Preferences", comment: "恢复默认：确认标题")
        alert.informativeText = NSLocalizedString("Preferences.ResetAll.Confirm.Message",
                                                  tableName: "Preferences", comment: "恢复默认：确认内容")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Preferences.ResetAll.Confirm.Reset",
                                                     tableName: "Preferences", comment: "恢复默认：确认按钮"))
        alert.addButton(withTitle: NSLocalizedString("Preferences.ResetAll.Confirm.Cancel",
                                                     tableName: "Preferences", comment: "恢复默认：取消按钮"))
        guard let window else {
            return
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.preferences.resetToDefaults()
            }
        }
    }

    // MARK: - 私有

    /// 装配窗口内容：左侧目录（source list）+ 右侧内容容器（页视图 + 底部"全部恢复默认"）。
    private func assembleContent() {
        // 左侧目录
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page"))
        sidebarTableView.addTableColumn(column)
        sidebarTableView.headerView = nil
        sidebarTableView.style = .sourceList
        // 选中态用中性灰（自绘），不采用系统强调色蓝
        sidebarTableView.selectionHighlightStyle = .none
        sidebarTableView.rowSizeStyle = .default
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self

        let sidebarScrollView = NSScrollView(frame: .zero)
        sidebarScrollView.documentView = sidebarTableView
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.drawsBackground = false

        let sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarScrollView
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 160
        sidebarItem.maximumThickness = 240
        sidebarItem.canCollapse = false
        splitViewController.addSplitViewItem(sidebarItem)

        // 右侧内容容器
        detailContainerView.translatesAutoresizingMaskIntoConstraints = false
        let detailViewController = NSViewController()
        detailViewController.view = detailContainerView
        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.minimumThickness = 380
        splitViewController.addSplitViewItem(detailItem)

        // 底部"全部恢复默认"按钮（随内容区，不随页切换重建）
        let resetButton = NSButton(
            title: NSLocalizedString("Preferences.ResetAll", tableName: "Preferences",
                                     comment: "偏好设置：全部恢复默认按钮"),
            target: self,
            action: #selector(resetAllPreferences(_:))
        )
        resetButton.bezelStyle = .rounded
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        detailContainerView.addSubview(resetButton)
        self.resetButton = resetButton
        NSLayoutConstraint.activate([
            resetButton.trailingAnchor.constraint(equalTo: detailContainerView.trailingAnchor,
                                                  constant: -16),
            resetButton.bottomAnchor.constraint(equalTo: detailContainerView.bottomAnchor,
                                                constant: -12),
        ])

        window?.contentViewController = splitViewController
    }

    /// 切换右侧内容页。
    /// - Parameter page: 目标页
    private func show(page: Page) {
        guard page != currentPage else {
            return
        }
        currentPage = page

        let viewController = pageViewController(for: page)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        for subview in detailContainerView.subviews where subview !== resetButton {
            subview.removeFromSuperview()
        }
        detailContainerView.addSubview(viewController.view, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: detailContainerView.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: detailContainerView.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: detailContainerView.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: detailContainerView.bottomAnchor,
                                                        constant: -44), // 底部留出"全部恢复默认"行
        ])
        sidebarTableView.selectRowIndexes(IndexSet(integer: page.rawValue),
                                          byExtendingSelection: false)
    }

    /// 取页内容视图控制器（懒创建并缓存）。
    /// - Parameter page: 目标页
    /// - Returns: 页视图控制器
    private func pageViewController(for page: Page) -> NSViewController {
        if let cached = pageViewControllers[page] {
            return cached
        }
        let viewController: NSViewController
        switch page {
        case .general:
            viewController = NPGeneralPreferencesViewController(preferences: preferences)
        case .editor:
            viewController = NPEditorPreferencesViewController(preferences: preferences)
        }
        pageViewControllers[page] = viewController
        return viewController
    }
}

// MARK: - NSTableViewDataSource

extension NPPreferencesWindowController: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        Page.allCases.count
    }
}

// MARK: - NSTableViewDelegate

extension NPPreferencesWindowController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView,
                   rowViewForRow row: Int) -> NSTableRowView? {
        // 自绘中性灰选中态（selectionHighlightStyle = .none 时 AppKit 不画默认高亮）
        NPPreferencesRowView()
    }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let page = Page.allCases[row]
        let identifier = NSUserInterfaceItemIdentifier("PageCell")
        let cell: NPSidebarCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NPSidebarCellView {
            cell = reused
        } else {
            cell = NPSidebarCellView(frame: .zero)
            cell.identifier = identifier
        }
        cell.iconView.image = NSImage(systemSymbolName: page.symbolName,
                                      accessibilityDescription: page.title)
        cell.label.stringValue = page.title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        guard row >= 0, let page = Page(rawValue: row) else {
            return
        }
        show(page: page)
    }
}

// MARK: - 中性灰选中行

/// 目录行视图：选中时绘制中性灰圆角背景（不依赖系统强调色），
/// 浅色/深色模式下均可读（半透明白叠加）。
@MainActor
private final class NPPreferencesRowView: NSTableRowView {

    /// 选中态变化时强制重绘：`selectionHighlightStyle = .none` 下 AppKit 不自动
    /// 重绘行，否则取消选中的旧行会残留灰色背景。
    override var isSelected: Bool {
        didSet { needsDisplay = true }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else {
            return
        }
        let selectionColor = NSColor(calibratedWhite: 0.5, alpha: 0.22)
        let rect = bounds.insetBy(dx: 3, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        selectionColor.setFill()
        path.fill()
    }
}

/// 目录单元格视图：普通 `NSView` 自持图标与文字，颜色固定为 label 色。
/// 不使用 `NSTableCellView`——它会在行选中时把文字/图标改写成系统高亮色，
/// 即使拦截 `backgroundStyle` 也可能被其内部时序覆盖（实测选中行文字变蓝）。
@MainActor
private final class NPSidebarCellView: NSView {

    /// 目录图标
    let iconView = NSImageView(frame: .zero)
    /// 目录文字
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.contentTintColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .labelColor
        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("本工程不使用 nib/storyboard（纯代码布局）")
    }
}
