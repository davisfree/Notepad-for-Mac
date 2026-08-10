//
//  NPStatusBarButton.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 状态栏可点击信息块（无边框按钮，hover 时背景略深，`02_UI_DESIGN.md` 5.4）。
@MainActor
final class NPStatusBarButton: NSButton {

    // MARK: - 常量

    /// 状态栏字号（02 §3.2）
    private static let fontSize: CGFloat = 11.0
    /// 水平内边距（左右各 8pt）
    private static let horizontalPadding: CGFloat = 16.0

    // MARK: - 回调

    /// 点击回调
    var onClick: (() -> Void)?

    // MARK: - 状态

    /// 悬停状态（驱动 hover 背景）
    private var isHovering = false
    /// 当前纯文本标题（外观变化时按新配色重建）
    private var currentText = ""

    /// 悬停追踪区域
    private var trackingArea: NSTrackingArea?

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        target = self
        action = #selector(handleClick(_:))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isBordered = false
        wantsLayer = true
        target = self
        action = #selector(handleClick(_:))
    }

    // MARK: - 标题

    /// 更新显示文案（状态栏 11pt、调色板文字色）。
    /// - Parameter text: 文案
    func updateTitle(_ text: String) {
        currentText = text
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Self.fontSize),
            .foregroundColor: NPColorPalette.statusBarText
        ])
    }

    /// 水平方向留出内边距。
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += Self.horizontalPadding
        return size
    }

    // MARK: - 点击

    /// 转发点击到闭包回调。
    /// - Parameter sender: 按钮
    @objc private func handleClick(_ sender: Any?) {
        onClick?()
    }

    // MARK: - 悬停

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

    /// 鼠标进入：显示 hover 背景。
    /// - Parameter event: 事件
    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateHoverBackground()
    }

    /// 鼠标离开：清除 hover 背景。
    /// - Parameter event: 事件
    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateHoverBackground()
    }

    /// 外观变化时刷新 hover 背景与标题配色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverBackground()
        updateTitle(currentText)
    }

    /// 按悬停状态更新背景色（动态色在当前有效外观下解析）。
    private func updateHoverBackground() {
        guard isHovering else {
            layer?.backgroundColor = nil
            return
        }
        var cgColor = NPColorPalette.statusBarItemHover.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cgColor = NPColorPalette.statusBarItemHover.cgColor
        }
        layer?.backgroundColor = cgColor
    }
}
