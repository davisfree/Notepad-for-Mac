//
//  NPStatusBarView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 状态栏委托（点击各信息块弹出对应菜单/对话框，PRD 4.3；所有回调均在主线程触发）。
@MainActor
protocol NPStatusBarDelegate: AnyObject {
    /// 点击 "Ln, Col"：弹出"转到行"
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapLineColumn(_ statusBar: NPStatusBarView)
    /// 点击缩放比例：弹出缩放选择菜单
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapZoomLevel(_ statusBar: NPStatusBarView)
    /// 点击换行符：弹出 CRLF / LF / CR 切换菜单
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapLineEnding(_ statusBar: NPStatusBarView)
    /// 点击编码：弹出编码切换菜单
    /// - Parameter statusBar: 状态栏视图
    func statusBarDidTapEncoding(_ statusBar: NPStatusBarView)
}

/// 底部状态栏视图（高度固定 22pt，见 `02_UI_DESIGN.md` 5.4）。
///
/// 布局从左到右：Ln X, Col Y ｜ 缩放% ｜ 换行符 ｜ 编码（PRD FR-012 顺序）；
/// Ln/Col 左对齐，其余信息块右对齐（02 §5.4）。
/// 可见性直接使用 `NSView.isHidden`，不单独引入状态（避免双状态失步）；
/// 开关动作（视图 → 状态栏 ⌘/）由窗口控制器读写 isHidden。
@MainActor
final class NPStatusBarView: NSView {

    // MARK: - 常量

    /// 状态栏高度（02 §5.4，严格 22pt）
    static let height: CGFloat = 22.0

    // MARK: - 委托

    weak var delegate: NPStatusBarDelegate?

    // MARK: - 属性

    /// 当前行号
    var lineNumber: Int = 1 {
        didSet { updateLineColumnText() }
    }

    /// 当前列号
    var columnNumber: Int = 1 {
        didSet { updateLineColumnText() }
    }

    /// 当前缩放比例（1.0 = 100%）
    var zoomLevel: Double = 1.0 {
        didSet { zoomButton.updateTitle(NPStatusBarFormatter.zoomText(zoomLevel)) }
    }

    /// 当前换行符格式
    var lineEnding: NPLineEnding = .lf {
        didSet { lineEndingButton.updateTitle(lineEnding.displayName) }
    }

    /// 当前编码
    var encoding: String.Encoding = .utf8 {
        didSet { updateEncodingText() }
    }

    /// 编码是否带 BOM（用于 "UTF-8 BOM" 显示；02 §3.3 编码显示清单所需，契约 §3.1 之外的附加属性）
    var encodingHasBOM: Bool = false {
        didSet { updateEncodingText() }
    }

    // MARK: - 子视图

    /// 行列信息块（左对齐）
    private let lineColumnButton = NPStatusBarButton(frame: .zero)
    /// 缩放信息块
    private let zoomButton = NPStatusBarButton(frame: .zero)
    /// 换行符信息块
    private let lineEndingButton = NPStatusBarButton(frame: .zero)
    /// 编码信息块（右对齐）
    private let encodingButton = NPStatusBarButton(frame: .zero)

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 装配信息块按钮与水平布局。
    private func setup() {
        wantsLayer = true
        refreshBackground()

        lineColumnButton.onClick = { [weak self] in
            guard let self, let delegate else { return }
            delegate.statusBarDidTapLineColumn(self)
        }
        zoomButton.onClick = { [weak self] in
            guard let self, let delegate else { return }
            delegate.statusBarDidTapZoomLevel(self)
        }
        lineEndingButton.onClick = { [weak self] in
            guard let self, let delegate else { return }
            delegate.statusBarDidTapLineEnding(self)
        }
        encodingButton.onClick = { [weak self] in
            guard let self, let delegate else { return }
            delegate.statusBarDidTapEncoding(self)
        }

        // 弹性占位：Ln/Col 居左，其余信息块居右（02 §5.4）
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16.0 // 02 §4.3 状态栏各信息块间距
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12) // 02 §4.3 状态栏内边距
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(lineColumnButton)
        stack.addArrangedSubview(spacer)
        stack.addArrangedSubview(zoomButton)
        stack.addArrangedSubview(lineEndingButton)
        stack.addArrangedSubview(encodingButton)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        updateLineColumnText()
        zoomButton.updateTitle(NPStatusBarFormatter.zoomText(zoomLevel))
        lineEndingButton.updateTitle(lineEnding.displayName)
        updateEncodingText()
    }

    // MARK: - 绘制

    /// 绘制顶部 1pt 边框（02 §5.4）。
    /// - Parameter dirtyRect: 待绘制区域
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NPColorPalette.statusBarBorder.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// 外观变化时刷新背景与边框（动态颜色在 draw 时解析，此处触发重绘与背景更新）。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
        needsDisplay = true
    }

    // MARK: - 私有

    /// 刷新状态栏底色（动态色切换到当前有效外观下解析，避免主题切换瞬间解析成旧外观）。
    private func refreshBackground() {
        var cgColor = NPColorPalette.statusBarBackground.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cgColor = NPColorPalette.statusBarBackground.cgColor
        }
        layer?.backgroundColor = cgColor
    }

    /// 刷新行列文案。
    private func updateLineColumnText() {
        lineColumnButton.updateTitle(NPStatusBarFormatter.lineColumnText(line: lineNumber, column: columnNumber))
    }

    /// 刷新编码文案。
    private func updateEncodingText() {
        encodingButton.updateTitle(NPStatusBarFormatter.encodingName(for: encoding, hasBOM: encodingHasBOM))
    }
}
