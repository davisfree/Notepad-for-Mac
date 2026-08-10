//
//  NPFindBarView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 匹配结果统计（"3/17" 样式展示）。
struct NPMatchResult {
    /// 当前匹配项序号（从 1 开始）
    let currentIndex: Int
    /// 匹配总数
    let totalCount: Int
}

/// 查找栏委托（交互全部经委托驱动，视图不直接引用查找逻辑；所有回调均在主线程触发）。
@MainActor
protocol NPFindBarDelegate: AnyObject {
    /// 查找文本变化（实时查找）
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - text: 当前查找文本
    func findBar(_ findBar: NPFindBarView, didChangeFindText text: String)
    /// 替换文本变化
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - text: 当前替换文本
    func findBar(_ findBar: NPFindBarView, didChangeReplaceText text: String)
    /// 请求查找下一个
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestFindNext(_ findBar: NPFindBarView)
    /// 请求查找上一个
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestFindPrevious(_ findBar: NPFindBarView)
    /// 请求替换当前匹配
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestReplace(_ findBar: NPFindBarView)
    /// 请求全部替换
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestReplaceAll(_ findBar: NPFindBarView)
    /// 查找选项变化
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - options: 新选项
    func findBarDidChangeOptions(_ findBar: NPFindBarView, options: NPFindOptions)
    /// 请求关闭查找栏
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestClose(_ findBar: NPFindBarView)
}

/// 查找/替换栏视图（位于编辑区上方、显示时推动编辑区下移不遮挡内容，PRD FR-004、02 §5.2/5.3）。
///
/// 单行高 44pt，替换模式展开第二行后 76pt；背景为 `NPColorPalette.findBarBackground` 纯色
/// （v1.3 修订：原 `NSVisualEffectView` 毛玻璃在浅色下与编辑区背景难区分，改为色板纯色）。
/// 选项区仅为一个"区分大小写"复选框，直接并入本视图，不单独拆 `NPFindOptionsView`。
@MainActor
final class NPFindBarView: NSView {

    // MARK: - 常量

    /// 单行高度（02 §5.2）
    static let singleLineHeight: CGFloat = 44.0
    /// 替换模式展开高度（02 §5.2）
    static let expandedHeight: CGFloat = 76.0
    /// 输入框高度（02 §5.2）
    private static let fieldHeight: CGFloat = 24.0

    // MARK: - 委托

    weak var delegate: NPFindBarDelegate?

    // MARK: - 回调

    /// 高度变化回调（替换模式展开/收起，供挂载方更新布局约束）
    var onHeightChange: ((CGFloat) -> Void)?

    // MARK: - 子视图

    /// 查找输入框
    private let findField = NSTextField()
    /// 替换输入框
    private let replaceField = NSTextField()
    /// 匹配统计标签
    private let matchLabel = NSTextField(labelWithString: "")
    /// "区分大小写"复选框
    private let caseSensitiveCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    /// 替换行（替换模式时展开）
    private let replaceRow = NSStackView()
    /// 替换输入框左缩进占位（宽度跟随折叠箭头，与查找输入框左缘对齐）
    private let replaceIndentSpacer = NSView()
    /// 替换区域折叠/展开切换按钮（查找输入框左侧，对齐 Win11：收起 ∧、展开 ∨）
    private lazy var toggleReplaceButton: NSButton = Self.makeIconButton(
        symbol: "chevron.up", fallbackTitle: "∧",
        accessibilityLabel: NSLocalizedString("FindBar.ToggleReplace", comment: "查找栏：折叠/展开替换"),
        action: #selector(handleToggleReplace(_:)), target: self)

    // MARK: - 属性

    /// 当前查找文本（赋值不触发委托回调）
    var findText: String {
        get { findField.stringValue }
        set { findField.stringValue = newValue }
    }

    /// 当前替换文本（赋值不触发委托回调）
    var replaceText: String {
        get { replaceField.stringValue }
        set { replaceField.stringValue = newValue }
    }

    /// 是否显示替换区域
    var isReplaceMode: Bool = false {
        didSet {
            guard isReplaceMode != oldValue else {
                return
            }
            replaceRow.isHidden = !isReplaceMode
            updateToggleChevron()
            onHeightChange?(isReplaceMode ? Self.expandedHeight : Self.singleLineHeight)
        }
    }

    /// 查找选项（"区分大小写"复选框状态映射到 `NPFindOptions.caseSensitive`）
    var options: NPFindOptions {
        get {
            caseSensitiveCheckbox.state == .on ? [.caseSensitive] : []
        }
        set {
            caseSensitiveCheckbox.state = newValue.contains(.caseSensitive) ? .on : .off
        }
    }

    /// 匹配结果统计（"3/17" 样式展示；总数为 0 时显示"未找到"，`nil` 隐藏）
    var matchResult: NPMatchResult? {
        didSet { updateMatchLabel() }
    }

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    /// 装配背景与两行控件。
    private func setup() {
        wantsLayer = true
        refreshBackground()

        configureFields()
        let findRow = makeFindRow()
        configureReplaceRow()
        replaceRow.isHidden = true

        let container = NSStackView(views: [findRow, replaceRow])
        container.orientation = .vertical
        container.spacing = 8.0
        container.edgeInsets = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8) // 02 §4.3 查找栏内边距
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            // 两行显式等宽撑满容器（垂直 NSStackView 默认按内容居中，行内容不同会导致整行错位）
            findRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -16),
            replaceRow.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -16),
            findField.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            replaceField.heightAnchor.constraint(equalToConstant: Self.fieldHeight),
            // 替换输入框与查找输入框等宽
            replaceField.widthAnchor.constraint(equalTo: findField.widthAnchor),
            // 替换行缩进跟随折叠箭头实际宽度
            replaceIndentSpacer.widthAnchor.constraint(equalTo: toggleReplaceButton.widthAnchor)
        ])
    }

    /// 配置输入框与统计标签。
    private func configureFields() {
        findField.placeholderString = NSLocalizedString("FindBar.FindPlaceholder", comment: "查找栏：查找占位")
        findField.bezelStyle = .roundedBezel
        findField.delegate = self
        replaceField.placeholderString = NSLocalizedString("FindBar.ReplacePlaceholder", comment: "查找栏：替换占位")
        replaceField.bezelStyle = .roundedBezel
        replaceField.delegate = self
        matchLabel.font = NSFont.systemFont(ofSize: 11.0)
        matchLabel.textColor = .secondaryLabelColor
        matchLabel.isHidden = true
        matchLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    /// 装配查找行（输入框、统计、上一个/下一个、区分大小写、关闭）。
    /// - Returns: 查找行视图
    private func makeFindRow() -> NSStackView {
        let previousButton = Self.makeIconButton(symbol: "chevron.up", fallbackTitle: "∧",
                                                 accessibilityLabel: NSLocalizedString("FindBar.FindPrevious",
                                                                                       comment: "查找栏：上一个"),
                                                 action: #selector(handleFindPrevious(_:)), target: self)
        let nextButton = Self.makeIconButton(symbol: "chevron.down", fallbackTitle: "∨",
                                             accessibilityLabel: NSLocalizedString("FindBar.FindNext",
                                                                                   comment: "查找栏：下一个"),
                                             action: #selector(handleFindNext(_:)), target: self)
        let closeButton = Self.makeIconButton(symbol: "xmark", fallbackTitle: "×",
                                              accessibilityLabel: NSLocalizedString("FindBar.Close",
                                                                                    comment: "查找栏：关闭"),
                                              action: #selector(handleClose(_:)), target: self)
        caseSensitiveCheckbox.title = NSLocalizedString("FindBar.CaseSensitive", comment: "查找栏：区分大小写")
        caseSensitiveCheckbox.font = NSFont.systemFont(ofSize: 11.0)
        caseSensitiveCheckbox.target = self
        caseSensitiveCheckbox.action = #selector(handleOptionsChange(_:))
        caseSensitiveCheckbox.setContentHuggingPriority(.required, for: .horizontal)

        findField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [toggleReplaceButton, findField, matchLabel, previousButton, nextButton,
                                      caseSensitiveCheckbox, closeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8.0
        return row
    }

    /// 装配替换行（替换输入框、替换/全部替换按钮）。
    private func configureReplaceRow() {
        let replaceButton = NSButton(title: NSLocalizedString("FindBar.Replace", comment: "查找栏：替换"),
                                     target: self, action: #selector(handleReplace(_:)))
        replaceButton.bezelStyle = .rounded
        let replaceAllButton = NSButton(title: NSLocalizedString("FindBar.ReplaceAll", comment: "查找栏：全部替换"),
                                        target: self, action: #selector(handleReplaceAll(_:)))
        replaceAllButton.bezelStyle = .rounded
        replaceAllButton.bezelColor = NPColorPalette.selectionBackground // 02 §5.3 主按钮蓝
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceRow.orientation = .horizontal
        replaceRow.alignment = .centerY
        replaceRow.spacing = 8.0
        replaceRow.addArrangedSubview(replaceIndentSpacer)
        replaceRow.addArrangedSubview(replaceField)
        replaceRow.addArrangedSubview(replaceButton)
        replaceRow.addArrangedSubview(replaceAllButton)
    }

    /// 创建无边框图标按钮（SF Symbol 不可用时回退字符标题）。
    /// - Parameters:
    ///   - symbol: SF Symbol 名称
    ///   - fallbackTitle: 回退标题
    ///   - accessibilityLabel: 无障碍标签
    ///   - action: 动作
    ///   - target: 目标
    /// - Returns: 按钮
    private static func makeIconButton(symbol: String, fallbackTitle: String, accessibilityLabel: String,
                                       action: Selector, target: AnyObject) -> NSButton {
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel) {
            button = NSButton(image: image, target: target, action: action)
            button.isBordered = false
        } else {
            button = NSButton(title: fallbackTitle, target: target, action: action)
            button.isBordered = false
        }
        button.setAccessibilityLabel(accessibilityLabel)
        button.widthAnchor.constraint(equalToConstant: 24.0).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24.0).isActive = true
        return button
    }

    /// 光标跟踪区域（鼠标在栏内移动时强制箭头光标）
    private var cursorTrackingArea: NSTrackingArea?

    // MARK: - 方法

    /// 光标区域：查找栏整体显示箭头，输入框内由 AppKit 自动显示 I 形光标。
    /// 下层文本视图会反复重挂自己的 I 形光标矩形并压到最上层，仅靠 addCursorRect 压不住，
    /// 因此另加跟踪区域在 mouseMoved/mouseEntered 时主动重置光标（输入框与字段编辑器除外）。
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    /// 跟踪区域随可见区域自动更新。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    /// 鼠标进入查找栏：非输入区域重置为箭头光标。
    /// - Parameter event: 鼠标事件
    override func mouseEntered(with event: NSEvent) {
        resetArrowCursorIfNotOverField(event)
    }

    /// 鼠标在查找栏内移动：非输入区域保持箭头光标。
    /// - Parameter event: 鼠标事件
    override func mouseMoved(with event: NSEvent) {
        resetArrowCursorIfNotOverField(event)
    }

    // MARK: - 外观

    /// 外观变化时刷新背景（动态色在层背景赋值时解析，须在此重解析重设，见状态栏同模式）。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    /// 刷新查找栏底色（动态色切换到当前有效外观下解析，避免主题切换瞬间解析成旧外观）。
    private func refreshBackground() {
        var cgColor = NPColorPalette.findBarBackground.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cgColor = NPColorPalette.findBarBackground.cgColor
        }
        layer?.backgroundColor = cgColor
    }

    /// 命中点为输入框（或其字段编辑器 NSTextView）时保留 I 形光标，否则强制箭头。
    /// - Parameter event: 鼠标事件
    private func resetArrowCursorIfNotOverField(_ event: NSEvent) {
        let hit = hitTest(convert(event.locationInWindow, from: nil))
        if hit is NSTextField || hit is NSTextView {
            return
        }
        NSCursor.arrow.set()
    }

    /// 聚焦到查找输入框。
    func focusFindField() {
        window?.makeFirstResponder(findField)
    }

    /// 选中查找输入框中的文本。
    func selectFindText() {
        findField.selectText(nil)
    }

    // MARK: - 控件动作

    /// 上一个匹配。
    /// - Parameter sender: 按钮
    @objc private func handleFindPrevious(_ sender: Any?) {
        delegate?.findBarDidRequestFindPrevious(self)
    }

    /// 下一个匹配。
    /// - Parameter sender: 按钮
    @objc private func handleFindNext(_ sender: Any?) {
        delegate?.findBarDidRequestFindNext(self)
    }

    /// 折叠/展开替换区域。
    /// - Parameter sender: 折叠箭头按钮
    @objc private func handleToggleReplace(_ sender: Any?) {
        isReplaceMode.toggle()
    }

    /// 替换当前匹配。
    /// - Parameter sender: 按钮
    @objc private func handleReplace(_ sender: Any?) {
        delegate?.findBarDidRequestReplace(self)
    }

    /// 全部替换。
    /// - Parameter sender: 按钮
    @objc private func handleReplaceAll(_ sender: Any?) {
        delegate?.findBarDidRequestReplaceAll(self)
    }

    /// 选项变化（区分大小写复选框）。
    /// - Parameter sender: 复选框
    @objc private func handleOptionsChange(_ sender: Any?) {
        delegate?.findBarDidChangeOptions(self, options: options)
    }

    /// 关闭查找栏。
    /// - Parameter sender: 按钮
    @objc private func handleClose(_ sender: Any?) {
        delegate?.findBarDidRequestClose(self)
    }

    // MARK: - 私有

    /// 刷新折叠箭头方向（收起 ∧ 提示可展开，展开 ∨ 提示可收起）。
    private func updateToggleChevron() {
        let label = toggleReplaceButton.accessibilityLabel()
        if let image = NSImage(systemSymbolName: isReplaceMode ? "chevron.down" : "chevron.up",
                               accessibilityDescription: label) {
            toggleReplaceButton.image = image
            toggleReplaceButton.title = ""
        } else {
            toggleReplaceButton.image = nil
            toggleReplaceButton.title = isReplaceMode ? "∨" : "∧"
        }
    }

    /// 刷新匹配统计标签。
    private func updateMatchLabel() {
        guard let matchResult else {
            matchLabel.isHidden = true
            return
        }
        matchLabel.isHidden = false
        if matchResult.totalCount == 0 {
            matchLabel.stringValue = NSLocalizedString("FindBar.NoMatches", comment: "查找栏：未找到")
        } else {
            matchLabel.stringValue = "\(matchResult.currentIndex)/\(matchResult.totalCount)"
        }
    }
}

// MARK: - NSTextFieldDelegate

extension NPFindBarView: NSTextFieldDelegate {
    /// 输入框文本变化：区分查找/替换框转发委托（实时查找）。
    /// - Parameter notification: 变更通知
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }
        if field === findField {
            delegate?.findBar(self, didChangeFindText: field.stringValue)
        } else if field === replaceField {
            delegate?.findBar(self, didChangeReplaceText: field.stringValue)
        }
    }
}
