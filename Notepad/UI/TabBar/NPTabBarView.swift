//
//  NPTabBarView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 标签项数据。
struct NPTabItem {
    /// 唯一标识
    let identifier: UUID
    /// 标题（文件名）
    let title: String
    /// 文件 URL（未保存文档为 nil）
    let fileURL: URL?
    /// 是否有未保存更改
    var isModified: Bool
}

/// 标签栏委托（所有回调均在主线程触发）。
@MainActor
protocol NPTabBarDelegate: AnyObject {
    /// 选中标签
    /// - Parameters:
    ///   - tabBar: 标签栏视图
    ///   - index: 标签索引
    func tabBar(_ tabBar: NPTabBarView, didSelectTabAt index: Int)
    /// 关闭标签
    /// - Parameters:
    ///   - tabBar: 标签栏视图
    ///   - index: 标签索引
    func tabBar(_ tabBar: NPTabBarView, didCloseTabAt index: Int)

    /// 拖拽排序完成（PRD FR-002）
    /// - Parameters:
    ///   - tabBar: 标签栏视图
    ///   - sourceIndex: 源索引
    ///   - destinationIndex: 目标索引
    func tabBar(_ tabBar: NPTabBarView, didMoveTabFrom sourceIndex: Int, to destinationIndex: Int)

    /// 标签被拖出窗口区域：由窗口控制器将其迁移为新窗口（PRD FR-002）
    /// - Parameters:
    ///   - tabBar: 标签栏视图
    ///   - index: 标签索引
    func tabBar(_ tabBar: NPTabBarView, didDragOutTabAt index: Int)

    /// 右键菜单（关闭 / 关闭其他 / 关闭右侧 / 复制标签 / 在 Finder 中显示）。
    /// 返回 nil 使用默认菜单；菜单动作由委托方以 target/action 方式处理
    /// - Parameters:
    ///   - tabBar: 标签栏视图
    ///   - index: 标签索引
    /// - Returns: 上下文菜单
    func tabBar(_ tabBar: NPTabBarView, didRequestContextMenuForTabAt index: Int) -> NSMenu?

    /// 点击右端"+"按钮（新建标签页）。
    /// 语义与菜单"文件 → 新建标签页（⌘N）"一致：新标签插入当前窗口的最左端。
    /// - Parameter tabBar: 标签栏视图
    func tabBarDidRequestNewTab(_ tabBar: NPTabBarView)
}

/// 标签栏视图（高度固定 32pt；macOS 原生风格——标签为浮于栏背景上的圆角卡片，
/// 用户决策替代原 Win11 复刻规格，自绘架构与交互不变）。
///
/// 拖拽排序用手动鼠标追踪实现（不走 NSPasteboard，排序与拖出均在应用内完成）：
/// 拖拽中绘制 2pt 插入指示线（系统强调色），被拖标签降低不透明度作为占位；
/// 拖拽点超出标签栏区域 20pt 判定为拖出窗口（`NPTabGroupModel.isDragOut`）。
/// 相邻都未选中的标签之间绘制 1px 半透明分隔线。
@MainActor
final class NPTabBarView: NSView {

    // MARK: - 常量

    /// 标签栏高度（02 §5.1）
    static let height: CGFloat = 26.0
    /// 标签栏左端内缩（首张卡片起点，macOS 原生卡片布局）
    static let barLeadingInset: CGFloat = 4.0
    /// 右端"新建标签页"按钮尺寸（02 §5.1 的 `[+]`）
    static let newTabButtonSize: CGFloat = 22.0
    /// 右端"新建标签页"按钮距右侧内缩
    private static let newTabButtonTrailingInset: CGFloat = 4.0
    /// 右端按钮占位宽度：计算卡片可用宽度时预留，避免多标签溢出时卡片压在按钮下
    private static var newTabButtonAreaWidth: CGFloat {
        newTabButtonSize + newTabButtonTrailingInset * 2.0
    }
    /// 触发拖拽的最小位移
    private static let dragStartThreshold: CGFloat = 4.0

    // MARK: - 委托

    weak var delegate: NPTabBarDelegate?

    // MARK: - 属性

    /// 当前标签列表
    private(set) var tabs: [NPTabItem] = []

    /// 当前选中索引（越界赋值自动夹取）
    var selectedIndex: Int = -1 {
        didSet {
            let clamped = tabs.isEmpty ? -1 : min(max(selectedIndex, 0), tabs.count - 1)
            if clamped != selectedIndex {
                selectedIndex = clamped
                return
            }
            updateSelectionStyles()
        }
    }

    // MARK: - 子视图与拖拽状态

    /// 标签子视图（与 tabs 顺序一致）
    private var tabViews: [NPTabItemView] = []

    /// 拖拽状态
    private struct DragState {
        /// 源索引
        let sourceIndex: Int
        /// 按下点（标签栏坐标系）
        let startPoint: NSPoint
        /// 是否已触发拖拽（超过最小位移）
        var isDragging = false
        /// 当前插入位置（nil = 无指示线）
        var insertIndex: Int?
        /// 是否已拖出窗口区域
        var isDragOut = false
    }

    /// 当前拖拽状态
    private var dragState: DragState?

    /// 右端"新建标签页"按钮
    private let newTabButton = NSButton()

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        refreshBackground()
        setupNewTabButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        refreshBackground()
        setupNewTabButton()
    }

    /// 装配右端"新建标签页"按钮（无边框、悬停可点，不参与标签卡片布局）。
    private func setupNewTabButton() {
        let symbol = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12.0, weight: .medium))
        if let symbol {
            newTabButton.image = symbol
        } else {
            newTabButton.title = "+"
        }
        newTabButton.isBordered = false
        newTabButton.bezelStyle = .regularSquare
        newTabButton.contentTintColor = .secondaryLabelColor
        let title = NSLocalizedString("Menu.File.NewTab", comment: "标签栏右端新建标签页按钮")
        newTabButton.toolTip = title
        newTabButton.setAccessibilityLabel(title)
        newTabButton.target = self
        newTabButton.action = #selector(handleNewTabButton(_:))
        addSubview(newTabButton)
    }

    /// 右端"+"按钮动作：转发给委托（由控制器拉起"新建标签页"流程，与 ⌘N 同一路径）。
    /// - Parameter sender: 按钮
    @objc private func handleNewTabButton(_ sender: Any?) {
        delegate?.tabBarDidRequestNewTab(self)
    }

    /// 刷新标签栏底色（动态色切换到当前有效外观下解析，避免主题切换瞬间解析成旧外观）。
    private func refreshBackground() {
        var cgColor = NPColorPalette.tabBarBackground.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cgColor = NPColorPalette.tabBarBackground.cgColor
        }
        layer?.backgroundColor = cgColor
    }

    // MARK: - 标签管理

    /// 在指定位置插入标签（越界夹取到 `0...count`）。
    ///
    /// 唯一的标签入口：新建文档传 `at: 0`（最左端），打开文件/会话恢复等追加传 `at: tabs.count`。
    /// - Parameters:
    ///   - tab: 标签项
    ///   - index: 插入位置（`0` = 最左端）
    func insertTab(_ tab: NPTabItem, at index: Int) {
        let clamped = min(max(index, 0), tabs.count)
        tabs.insert(tab, at: clamped)
        let tabView = makeTabView(for: tab)
        tabViews.insert(tabView, at: clamped)
        addSubview(tabView)
        syncSubviewOrder()
        updateSelectionStyles()
        layoutCards()
        needsLayout = true
    }

    /// 保持卡片子视图顺序与 `tabs` / `tabViews` 逻辑顺序一致，并让右端"+"按钮始终在最上层。
    ///
    /// `addSubview` 只会把新视图追加到子视图列表末尾，因此前置插入（新增标签落在最左端）
    /// 会让卡片顺序与逻辑顺序不一致；卡片本身不重叠，但两者一致才能让绘制/命中测试
    /// 与布局断言按同一种顺序解读。
    private func syncSubviewOrder() {
        if tabViews.count > 1 {
            for index in 1 ..< tabViews.count {
                addSubview(tabViews[index], positioned: .above, relativeTo: tabViews[index - 1])
            }
        }
        // "+"按钮置顶：多标签溢出时卡片可能滑到按钮区域，按钮必须仍可点
        addSubview(newTabButton, positioned: .above, relativeTo: nil)
    }

    /// 装配单个标签视图（选中/关闭/拖拽/右键回调均按 `tabViews` 中的当前位置解析索引）。
    /// - Parameter tab: 标签项
    /// - Returns: 标签视图
    private func makeTabView(for tab: NPTabItem) -> NPTabItemView {
        let tabView = NPTabItemView(frame: .zero)
        tabView.title = tab.title
        tabView.isModified = tab.isModified
        tabView.onSelect = { [weak self] in
            guard let self, let index = tabViews.firstIndex(of: tabView) else {
                return
            }
            delegate?.tabBar(self, didSelectTabAt: index)
        }
        tabView.onClose = { [weak self] in
            guard let self, let index = tabViews.firstIndex(of: tabView) else {
                return
            }
            delegate?.tabBar(self, didCloseTabAt: index)
        }
        tabView.onMouseDown = { [weak self] event in
            guard let self, let index = tabViews.firstIndex(of: tabView) else {
                return
            }
            beginDrag(at: index, event: event)
        }
        tabView.onMouseDragged = { [weak self] event in
            self?.updateDrag(with: event)
        }
        tabView.onMouseUp = { [weak self] event in
            self?.endDrag(with: event)
        }
        tabView.onContextMenu = { [weak self] event in
            guard let self, let index = tabViews.firstIndex(of: tabView) else {
                return
            }
            showContextMenu(for: index, event: event)
        }
        return tabView
    }

    /// 移除标签。
    /// - Parameter index: 标签索引
    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }
        tabs.remove(at: index)
        let removed = tabViews.remove(at: index)
        removed.removeFromSuperview()
        syncSubviewOrder()
        updateSelectionStyles()
        layoutCards()
        needsLayout = true
    }

    /// 更新标签状态（未保存时标题前显示圆点 ●，PRD FR-002）。
    /// - Parameters:
    ///   - index: 标签索引
    ///   - isModified: 是否有未保存更改
    func updateTab(at index: Int, isModified: Bool) {
        guard tabs.indices.contains(index) else {
            return
        }
        tabs[index].isModified = isModified
        tabViews[index].isModified = isModified
    }

    /// 更新标签标题（重命名/保存后；契约之外的附加方法）。
    /// - Parameters:
    ///   - index: 标签索引
    ///   - title: 新标题
    func updateTabTitle(at index: Int, title: String) {
        guard tabs.indices.contains(index) else {
            return
        }
        tabs[index] = NPTabItem(identifier: tabs[index].identifier, title: title,
                                fileURL: tabs[index].fileURL, isModified: tabs[index].isModified)
        tabViews[index].title = title
    }

    /// 全量重建标签视图（拖拽排序后按新顺序重建）。
    /// - Parameter newTabs: 新顺序的标签列表
    func reloadTabs(_ newTabs: [NPTabItem]) {
        for view in tabViews {
            view.removeFromSuperview()
        }
        tabs = []
        tabViews = []
        for tab in newTabs {
            insertTab(tab, at: tabs.count)
        }
        layoutCards()
        needsLayout = true
    }

    // MARK: - 布局

    /// 横向等宽布局标签卡片（宽度夹取 120–240pt；卡片垂直内缩 4pt、间距 2pt、左端内缩 4pt）。
    /// 右端为"新建标签页"按钮预留占位，卡片可用宽度不含该区域。
    override func layout() {
        super.layout()
        layoutNewTabButton()
        guard !tabViews.isEmpty else {
            needsDisplay = true
            return
        }
        layoutCards()
        needsDisplay = true
    }

    /// 立即按当前标签数与 bounds 重排卡片（增删标签后同步调用）。
    ///
    /// 必须显式调用：`layout()` 由 AppKit 在下一个更新周期才执行，期间新卡片会保持
    /// `frame == .zero`，即被画在标签栏最左端。
    private func layoutCards() {
        layoutNewTabButton()
        guard !tabViews.isEmpty else {
            return
        }
        let availableWidth = bounds.width - Self.newTabButtonAreaWidth
        let width = min(max(availableWidth / CGFloat(tabViews.count), NPTabItemView.minimumWidth),
                        NPTabItemView.maximumWidth)
        let cardHeight = bounds.height - NPTabItemView.cardVerticalInset * 2.0
        var xPosition: CGFloat = Self.barLeadingInset
        for tabView in tabViews {
            tabView.frame = NSRect(x: xPosition, y: NPTabItemView.cardVerticalInset,
                                   width: width - NPTabItemView.cardSpacing, height: cardHeight)
            xPosition += width
        }
    }

    /// 右端"+"按钮位置（右对齐、垂直居中）。
    private func layoutNewTabButton() {
        newTabButton.frame = NSRect(x: bounds.maxX - Self.newTabButtonTrailingInset - Self.newTabButtonSize,
                                    y: (bounds.height - Self.newTabButtonSize) / 2.0,
                                    width: Self.newTabButtonSize, height: Self.newTabButtonSize)
    }

    // MARK: - 绘制

    /// 绘制：相邻都未选中的标签之间 1px 半透明竖直分隔线、底部 1pt 边框、拖拽插入指示线
    /// （分隔线与指示线均走系统语义色，拖拽指示线为系统强调色）。
    /// - Parameter dirtyRect: 待绘制区域
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 相邻分隔线：仅相邻两个标签都未选中时可见（选中卡片自带边界）
        NSColor.separatorColor.setFill()
        for index in 0 ..< max(tabViews.count - 1, 0)
        where index != selectedIndex && index + 1 != selectedIndex {
            let lineX = tabViews[index].frame.maxX + NPTabItemView.cardSpacing / 2.0
            NSRect(x: lineX - 0.5, y: NPTabItemView.cardVerticalInset + 3,
                   width: 1, height: bounds.height - (NPTabItemView.cardVerticalInset + 3) * 2.0).fill()
        }
        // 底部 1pt 边框
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        // 拖拽插入指示线（2pt，系统强调色）
        if let insertIndex = dragState?.insertIndex, dragState?.isDragOut == false {
            let xPosition = insertionX(for: insertIndex)
            let indicatorRect = NSRect(x: xPosition - 1, y: 4, width: 2, height: bounds.height - 8)
            NSColor.controlAccentColor.setFill()
            indicatorRect.fill()
        }
    }

    // MARK: - 拖拽排序 / 拖出窗口

    /// 开始拖拽追踪。
    /// - Parameters:
    ///   - index: 源索引
    ///   - event: 鼠标按下事件
    private func beginDrag(at index: Int, event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragState = DragState(sourceIndex: index, startPoint: point)
    }

    /// 更新拖拽状态（触发判定、插入位置、拖出判定）。
    /// - Parameter event: 拖拽事件
    private func updateDrag(with event: NSEvent) {
        guard var state = dragState else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if !state.isDragging {
            let distance = hypot(point.x - state.startPoint.x, point.y - state.startPoint.y)
            guard distance > Self.dragStartThreshold else {
                return
            }
            state.isDragging = true
            tabViews[state.sourceIndex].isDragPlaceholder = true
        }
        state.isDragOut = NPTabGroupModel.isDragOut(point: point, in: bounds)
        state.insertIndex = state.isDragOut ? nil : insertionIndex(for: point)
        dragState = state
        needsDisplay = true
    }

    /// 结束拖拽：拖出窗口或落位排序。
    /// - Parameter event: 松开事件
    private func endDrag(with event: NSEvent) {
        guard let state = dragState else {
            return
        }
        defer {
            if tabViews.indices.contains(state.sourceIndex) {
                tabViews[state.sourceIndex].isDragPlaceholder = false
            }
            dragState = nil
            needsDisplay = true
        }
        guard state.isDragging else {
            return
        }
        if state.isDragOut {
            delegate?.tabBar(self, didDragOutTabAt: state.sourceIndex)
            return
        }
        if let destination = state.insertIndex, destination != state.sourceIndex {
            delegate?.tabBar(self, didMoveTabFrom: state.sourceIndex, to: destination)
        }
    }

    /// 按拖拽点 x 坐标计算插入位置。
    /// - Parameter point: 拖拽点（标签栏坐标系）
    /// - Returns: 插入索引（0...tabs.count-1）
    private func insertionIndex(for point: NSPoint) -> Int {
        guard !tabViews.isEmpty else {
            return 0
        }
        for (index, tabView) in tabViews.enumerated() where point.x < tabView.frame.midX {
            return index
        }
        return tabViews.count - 1
    }

    /// 插入指示线 x 坐标。
    /// - Parameter index: 插入索引
    /// - Returns: x 坐标
    private func insertionX(for index: Int) -> CGFloat {
        guard tabViews.indices.contains(index) else {
            return tabViews.last?.frame.maxX ?? 0
        }
        return tabViews[index].frame.minX
    }

    // MARK: - 右键菜单

    /// 弹出上下文菜单。
    /// - Parameters:
    ///   - index: 标签索引
    ///   - event: 右键事件
    private func showContextMenu(for index: Int, event: NSEvent) {
        guard let menu = delegate?.tabBar(self, didRequestContextMenuForTabAt: index) else {
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - 私有

    /// 同步子视图选中样式并刷新分隔线（选中卡片两侧的相邻分隔线隐藏）。
    private func updateSelectionStyles() {
        for (index, tabView) in tabViews.enumerated() {
            tabView.isSelected = index == selectedIndex
        }
        needsDisplay = true
    }

    /// 外观变化时刷新背景。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
        needsDisplay = true
    }
}
