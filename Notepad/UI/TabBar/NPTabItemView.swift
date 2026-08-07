//
//  NPTabItemView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 单标签视图（macOS 原生风格：浮于标签栏背景上的圆角卡片，Safari/Finder 方向）。
///
/// 视觉规格（用户决策，替代原 Win11 复刻规格，自绘架构与交互不变）：
/// - 卡片四边圆角 6pt，垂直内缩 4pt（栏高 32pt 内卡片高 24pt），卡片间距 2pt；
/// - 选中：明亮卡片色（`NSColor.controlBackgroundColor`）；未选中：透明，悬停微显；
/// - 关闭按钮在**左侧**（macOS 惯例），悬停/选中时显示，未选中更淡；
/// - 未保存圆点使用系统强调色（`NSColor.controlAccentColor`），与关闭按钮共槽位：
///   平时显示圆点，悬停/选中时让位给关闭按钮（Safari 式互换）；
/// - 深浅色模式经语义色自动适配。
@MainActor
final class NPTabItemView: NSView {

    // MARK: - 常量

    /// 最小宽度
    static let minimumWidth: CGFloat = 120.0
    /// 最大宽度
    static let maximumWidth: CGFloat = 240.0
    /// 卡片垂直内缩（栏高 26pt - 2×1pt = 卡片高 24pt，上下各留 1pt 间隙）
    static let cardVerticalInset: CGFloat = 1.0
    /// 卡片圆角（卡片高 24pt 的一半：左右两头呈半圆形的胶囊样式）
    static let cardCornerRadius: CGFloat = 12.0
    /// 卡片间距
    static let cardSpacing: CGFloat = 2.0
    /// 卡片左侧槽位（关闭按钮/圆点）起点内边距
    static let slotLeadingInset: CGFloat = 6.0
    /// 未保存圆点直径
    static let dotDiameter: CGFloat = 6.0
    /// 关闭按钮尺寸（槽位宽度，决定标题起点）
    static let closeButtonSize: CGFloat = 14.0
    /// 关闭图标实际绘制尺寸（比槽位小 2pt，视觉更轻盈）
    static let closeButtonIconSize: CGFloat = 12.0
    /// 关闭图标水平微调（向右 1pt）
    static let closeButtonNudge: CGFloat = 1.0
    /// 卡片右侧内边距
    private static let cardTrailingInset: CGFloat = 8.0
    /// 槽位与标题间距
    private static let slotSpacing: CGFloat = 6.0

    // MARK: - 回调

    /// 点击选中
    var onSelect: (() -> Void)?
    /// 点击关闭按钮
    var onClose: (() -> Void)?
    /// 鼠标按下（拖拽排序起点；坐标为事件原图）
    var onMouseDown: ((NSEvent) -> Void)?
    /// 拖拽中
    var onMouseDragged: ((NSEvent) -> Void)?
    /// 松开
    var onMouseUp: ((NSEvent) -> Void)?
    /// 右键菜单
    var onContextMenu: ((NSEvent) -> Void)?

    // MARK: - 属性

    /// 标签标题
    var title: String = "" {
        didSet { titleLabel.stringValue = title }
    }

    /// 是否未保存（左侧槽位显示系统强调色圆点 ●，悬停/选中时让位给关闭按钮）
    var isModified: Bool = false {
        didSet { updateSlotVisibility() }
    }

    /// 是否选中（明亮卡片色，未选中透明）
    var isSelected: Bool = false {
        didSet { updateStyle() }
    }

    /// 拖拽中（保留空白占位：降低不透明度）
    var isDragPlaceholder: Bool = false {
        didSet { alphaValue = isDragPlaceholder ? 0.3 : 1.0 }
    }

    // MARK: - 子视图

    /// 未保存圆点（系统强调色）
    private let dotView = NSView()
    /// 标题标签
    private let titleLabel = NSTextField(labelWithString: "")
    /// 关闭按钮（左侧，悬停/选中时显示）
    private let closeButton = NSButton()

    /// 悬停状态
    private var isHovering = false {
        didSet { updateStyle() }
    }

    /// 悬停追踪区域
    private var trackingArea: NSTrackingArea?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 装配子视图。
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = Self.cardCornerRadius // 四边圆角（默认 maskedCorners 含四角）

        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dotView.layer?.cornerRadius = Self.dotDiameter / 2.0
        dotView.isHidden = true
        addSubview(dotView)

        titleLabel.font = NSFont.systemFont(ofSize: 12.0)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        if let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10.0, weight: .regular)) {
            closeButton.image = image
        } else {
            closeButton.title = "×"
        }
        closeButton.isBordered = false
        closeButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(handleClose(_:))
        addSubview(closeButton)

        updateStyle()
    }

    // MARK: - 布局

    /// 布局子视图（左侧槽位[关闭按钮/圆点] - 标题）。
    override func layout() {
        super.layout()
        let midY = bounds.midY
        let slotX = Self.slotLeadingInset
        if !closeButton.isHidden {
            closeButton.frame = NSRect(x: slotX + Self.closeButtonNudge,
                                       y: midY - Self.closeButtonIconSize / 2.0,
                                       width: Self.closeButtonIconSize, height: Self.closeButtonIconSize)
        }
        if !dotView.isHidden {
            dotView.frame = NSRect(x: slotX + (Self.closeButtonSize - Self.dotDiameter) / 2.0,
                                   y: midY - Self.dotDiameter / 2.0,
                                   width: Self.dotDiameter, height: Self.dotDiameter)
        }
        let titleX = slotX + Self.closeButtonSize + Self.slotSpacing
        titleLabel.frame = NSRect(x: titleX, y: midY - 8.0,
                                  width: max(0, bounds.width - titleX - Self.cardTrailingInset),
                                  height: 16.0)
    }

    // MARK: - 事件

    /// 左键按下：选中并进入拖拽准备。
    /// - Parameter event: 事件
    override func mouseDown(with event: NSEvent) {
        onSelect?()
        onMouseDown?(event)
    }

    /// 拖拽中。
    /// - Parameter event: 事件
    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(event)
    }

    /// 松开。
    /// - Parameter event: 事件
    override func mouseUp(with event: NSEvent) {
        onMouseUp?(event)
    }

    /// 右键：上下文菜单。
    /// - Parameter event: 事件
    override func rightMouseDown(with event: NSEvent) {
        onContextMenu?(event)
    }

    /// 重建悬停追踪区域。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// 鼠标进入：显示关闭按钮与悬停底色。
    /// - Parameter event: 事件
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    /// 鼠标离开：恢复槽位与透明底色。
    /// - Parameter event: 事件
    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    /// 外观变化时刷新样式。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateStyle()
    }

    // MARK: - 私有

    /// 关闭按钮动作。
    /// - Parameter sender: 按钮
    @objc private func handleClose(_ sender: Any?) {
        onClose?()
    }

    /// 槽位可见性：悬停/选中显示关闭按钮（圆点让位），否则显示未保存圆点。
    private func updateSlotVisibility() {
        let showsClose = isHovering || isSelected
        closeButton.isHidden = !showsClose
        dotView.isHidden = showsClose || !isModified
        needsLayout = true
    }

    /// 按选中/悬停状态更新卡片底色、文字色与关闭按钮浓淡（全语义色，深浅色自适应）。
    private func updateStyle() {
        // 动态系统色必须切换到视图当前有效外观下解析再取 cgColor——
        // 直接取会按全局当前外观解析，主题切换瞬间解析成旧外观（颜色不跟随）
        var selectedBackground = NSColor.controlBackgroundColor.cgColor
        var hoverBackground = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectedBackground = NSColor.controlBackgroundColor.cgColor
            hoverBackground = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
        if isSelected {
            layer?.backgroundColor = selectedBackground
            titleLabel.textColor = .labelColor
            closeButton.contentTintColor = .secondaryLabelColor
        } else if isHovering {
            layer?.backgroundColor = hoverBackground
            titleLabel.textColor = .secondaryLabelColor
            closeButton.contentTintColor = .tertiaryLabelColor
        } else {
            layer?.backgroundColor = nil
            titleLabel.textColor = .secondaryLabelColor
            closeButton.contentTintColor = .tertiaryLabelColor
        }
        updateSlotVisibility()
    }
}
