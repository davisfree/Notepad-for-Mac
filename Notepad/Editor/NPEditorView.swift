//
//  NPEditorView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 文本编辑器视图，封装 `NPTextView`（内嵌于私有 `NSScrollView`）并提供扩展功能：
/// 行列计算、自动换行切换、字体缩放、查找高亮、转到行、时间戳插入。
///
/// 缩放采用**字体缩放**方案（仅放大编辑区字号，对齐 `02_UI_DESIGN.md` 8.2
/// "仅编辑区字体缩放，界面字体保持固定"），而非 `scaleUnitSquare`——后者会连带缩放
/// 后续挂载的查找栏等子视图。
@MainActor
final class NPEditorView: NSView {

    // MARK: - 委托

    weak var delegate: NPEditorDelegate?

    // MARK: - 常量

    /// 最小缩放比例（10%，PRD FR-015）
    private static let minimumZoomLevel = 0.1
    /// 最大缩放比例（500%，PRD FR-015）
    private static let maximumZoomLevel = 5.0

    // MARK: - 子视图

    /// 内嵌滚动视图
    private let scrollView = NSScrollView()
    /// 底层文本视图（显式装配 textStorage/layoutManager/textContainer；
    /// `init(frame:textContainer:)` 传 nil 不会建立文本系统，string 赋值将静默失败）
    private let textView = NPEditorView.makeTextView()

    // MARK: - 状态

    /// 基础字体（缩放系数为 1.0 时的字体）
    private var baseFont: NSFont = NPTextView.defaultFont()
    /// 当前缩放比例（已夹取到合法范围）
    private var storedZoomLevel: Double = 1.0
    /// 当前高亮的匹配范围（用于下次高亮前清除）
    private var highlightedRanges: [NSRange] = []
    /// 偏好变更通知观察者令牌（字体等全局项变化时同步已开窗口）
    private var preferencesObserver: NSObjectProtocol?

    // MARK: - 查找替换栏状态

    // 查找栏 UI 为 `NPFindBarView`（04 §3.3），挂载由 UI 层组合根（`NPFindBarController`）执行；
    // 本视图只维护可见性状态并经闭包发出显隐请求，不直接引用 UI 层类型（08 §3）。

    /// 查找栏是否可见
    private(set) var isFindBarVisible = false
    /// 替换栏是否可见（展开查找栏）
    private(set) var isReplaceBarVisible = false

    /// 查找栏显隐请求回调（visible：是否显示；replaceMode：是否展开替换区域）
    var onFindBarVisibilityChange: ((_ visible: Bool, _ replaceMode: Bool) -> Void)?

    /// "转到行"面板控制器（Editor 层同模块，随视图生命周期持有）
    private let goToLineController = NPGoToLineController()

    /// 文档总行数（至少 1，用于"转到行"输入校验）
    private var maxLineNumber: Int {
        Self.lineAndColumn(at: (text as NSString).length, in: text).line
    }

    /// 预填"转到行"面板的当前行号。
    private func configureGoToLineController() {
        goToLineController.currentLineProvider = { [weak self] in
            self?.currentLine ?? 1
        }
    }

    // MARK: - 属性

    /// 当前显示的文本
    var text: String {
        get { textView.string }
        set {
            textView.string = newValue
            // 内容被整体替换后旧匹配范围失效，清除高亮
            highlightMatches([], currentIndex: -1)
        }
    }

    /// 是否可编辑（大文件只读模式下置 false，PRD FR-001；契约之外的附加属性）
    var isEditable: Bool {
        get { textView.isEditable }
        set { textView.isEditable = newValue }
    }

    /// 当前选区范围
    var selectedRange: NSRange {
        get { textView.selectedRange() }
        set {
            textView.setSelectedRange(newValue)
            textView.scrollRangeToVisible(newValue)
        }
    }

    /// 当前光标位置（行号，从 1 开始）
    var currentLine: Int {
        Self.lineAndColumn(at: selectedRange.location, in: text).line
    }

    /// 当前光标位置（列号，从 1 开始）
    var currentColumn: Int {
        Self.lineAndColumn(at: selectedRange.location, in: text).column
    }

    /// 是否启用自动换行（Win11 Notepad 默认开启）
    var isWordWrapEnabled: Bool = true {
        didSet { applyWordWrap() }
    }

    /// 当前缩放比例（1.0 = 100%）。
    /// 合法范围 0.1 – 5.0（10%–500%，PRD FR-015），赋值越界时自动夹取。
    var zoomLevel: Double {
        get { storedZoomLevel }
        set {
            let clamped = min(max(newValue, Self.minimumZoomLevel), Self.maximumZoomLevel)
            guard clamped != storedZoomLevel else {
                return
            }
            storedZoomLevel = clamped
            applyEffectiveFont()
            delegate?.editorDidChangeZoomLevel(self, zoomLevel: clamped)
            NotificationCenter.default.post(
                name: NPNotificationNames.zoomLevelDidChange,
                object: self,
                userInfo: [NPNotificationNames.zoomLevelKey: NSNumber(value: clamped)]
            )
        }
    }

    /// 当前字体（缩放系数 1.0 时的基础字体；实际渲染字号随 `zoomLevel` 缩放）
    var font: NSFont {
        get { baseFont }
        set {
            baseFont = newValue
            applyEffectiveFont()
        }
    }

    // MARK: - 初始化

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupEditor()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupEditor()
    }

    /// 装配滚动视图与文本视图并应用默认配置。
    private func setupEditor() {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        addSubview(scrollView)

        textView.delegate = self
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        applyWordWrap()
        applyEffectiveFont()
        configureGoToLineController()
        observePreferences()
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
    }

    /// 订阅全局偏好变更：字体在偏好面板修改后同步到已开窗口（缩放系数保持不变）。
    private func observePreferences() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: NPNotificationNames.preferencesDidChange,
            object: NPPreferences.shared,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.font = NPPreferences.shared.font
            }
        }
    }

    /// 显式装配完整文本系统并创建底层文本视图。
    /// - Returns: 文本视图
    private static func makeTextView() -> NPTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        return NPTextView(frame: .zero, textContainer: textContainer)
    }

    // MARK: - 查找替换栏

    /// 显示查找栏（挂载由 UI 层组合根经 `onFindBarVisibilityChange` 执行）。
    func showFindBar() {
        isFindBarVisible = true
        isReplaceBarVisible = false
        onFindBarVisibilityChange?(true, false)
    }

    /// 隐藏查找栏（同时收起替换栏并清除匹配高亮）。
    func hideFindBar() {
        isFindBarVisible = false
        isReplaceBarVisible = false
        highlightMatches([], currentIndex: -1)
        onFindBarVisibilityChange?(false, false)
    }

    /// 显示替换栏（展开查找栏）。
    func showReplaceBar() {
        isFindBarVisible = true
        isReplaceBarVisible = true
        onFindBarVisibilityChange?(true, true)
    }

    /// 高亮匹配结果（由 `NPFindController` 计算后回传）。
    ///
    /// 通过 `NSLayoutManager` 临时属性实现，不改动 `NSTextStorage` 内容；
    /// 当前匹配项使用 Win11 蓝底白字，其余匹配项使用半透明黄底。
    /// - Parameters:
    ///   - ranges: 全部匹配范围
    ///   - currentIndex: 当前匹配项索引（越界时无当前项高亮）
    func highlightMatches(_ ranges: [NSRange], currentIndex: Int) {
        guard let layoutManager = textView.layoutManager else {
            return
        }
        for range in highlightedRanges {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
        highlightedRanges = ranges
        for (index, range) in ranges.enumerated() {
            if index == currentIndex {
                layoutManager.addTemporaryAttribute(.backgroundColor,
                                                    value: NPColorPalette.findCurrentMatchBackground,
                                                    forCharacterRange: range)
                layoutManager.addTemporaryAttribute(.foregroundColor,
                                                    value: NPColorPalette.findCurrentMatchText,
                                                    forCharacterRange: range)
            } else {
                layoutManager.addTemporaryAttribute(.backgroundColor,
                                                    value: NPColorPalette.findMatchBackground,
                                                    forCharacterRange: range)
            }
        }
    }

    // MARK: - 导航

    /// 跳转到指定行（选中该行内容并滚动可见）。
    /// - Parameter lineNumber: 行号（从 1 开始；越界时不做处理）
    func goToLine(_ lineNumber: Int) {
        guard let range = Self.rangeOfLine(lineNumber, in: text) else {
            return
        }
        selectRange(range)
    }

    /// 插入时间戳（PRD 菜单：编辑 → 时间/日期，F5；格式对齐 Win11，如 "15:30 2026/8/2"）。
    func insertTimestamp() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm yyyy/M/d"
        textView.insertText(formatter.string(from: Date()), replacementRange: textView.selectedRange())
    }

    // MARK: - 选择

    /// 全选
    func selectAllText() {
        textView.selectAll(nil)
    }

    /// 选择指定范围并滚动可见。
    /// - Parameter range: 目标范围（UTF-16 偏移）
    func selectRange(_ range: NSRange) {
        selectedRange = range
        window?.makeFirstResponder(textView)
    }

    // MARK: - 菜单动作（响应链，菜单 target 为 nil 时由本视图响应）

    /// 编辑 → 时间/日期（F5）。
    /// - Parameter sender: 菜单项
    @objc func insertTimestampAction(_ sender: Any?) {
        insertTimestamp()
    }

    /// 编辑 → 查找…（⌘F）。
    /// - Parameter sender: 菜单项
    @objc func showFindBarAction(_ sender: Any?) {
        showFindBar()
    }

    /// 编辑 → 替换…（⌥⌘F）。
    /// - Parameter sender: 菜单项
    @objc func showReplaceBarAction(_ sender: Any?) {
        showReplaceBar()
    }

    /// 编辑 → 查找下一个（⌘G）。
    /// - Parameter sender: 菜单项
    @objc func findNextAction(_ sender: Any?) {
        // TODO: 接入查找栏状态后驱动 NPEditorController 定位下一匹配（04 §3.3）
    }

    /// 编辑 → 查找上一个（⇧⌘G）。
    /// - Parameter sender: 菜单项
    @objc func findPreviousAction(_ sender: Any?) {
        // TODO: 接入查找栏状态后驱动 NPEditorController 定位上一匹配（04 §3.3）
    }

    /// 编辑 → 转到…（⌃G）：弹出"转到行"浮动面板。
    /// - Parameter sender: 菜单项
    @objc func goToLineAction(_ sender: Any?) {
        guard let window else {
            return
        }
        goToLineController.present(in: window, maxLine: maxLineNumber) { [weak self] lineNumber in
            guard let self, let lineNumber else {
                return
            }
            self.goToLine(lineNumber)
        }
    }

    /// 格式 → 自动换行（⌥⌘W）。全局开关写入偏好（PRD FR-016），本窗口即时生效。
    /// - Parameter sender: 菜单项
    @objc func toggleWordWrap(_ sender: Any?) {
        NPPreferences.shared.isWordWrapEnabled.toggle()
        isWordWrapEnabled = NPPreferences.shared.isWordWrapEnabled
    }

    /// 视图 → 缩放 → 放大（⌘+，步进 10%，对齐 Win11）。
    /// - Parameter sender: 菜单项
    @objc func zoomInAction(_ sender: Any?) {
        zoomLevel += NPConstants.zoomStep
    }

    /// 视图 → 缩放 → 缩小（⌘-，步进 10%）。
    /// - Parameter sender: 菜单项
    @objc func zoomOutAction(_ sender: Any?) {
        zoomLevel -= NPConstants.zoomStep
    }

    /// 视图 → 缩放 → 恢复默认（⌘0）。
    /// - Parameter sender: 菜单项
    @objc func resetZoomAction(_ sender: Any?) {
        zoomLevel = 1.0
    }

    /// 菜单项状态验证：自动换行勾选跟随全局偏好（PRD FR-016）。
    /// - Parameter menuItem: 待验证菜单项
    /// - Returns: 是否可用
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleWordWrap(_:)) {
            menuItem.state = NPPreferences.shared.isWordWrapEnabled ? .on : .off
        }
        return true
    }

    // MARK: - 行列计算（纯函数，可无 UI 测试）

    /// 计算文本中指定 UTF-16 偏移处的行列号（从 1 开始，基于 `\n` 计数）。
    /// - Parameters:
    ///   - location: UTF-16 偏移（自动夹取到文本范围内）
    ///   - text: 文本内容
    /// - Returns: 行列号（均从 1 开始）
    static func lineAndColumn(at location: Int, in text: String) -> (line: Int, column: Int) {
        let nsText = text as NSString
        let clamped = max(0, min(location, nsText.length))
        var line = 1
        var lineStart = 0
        var index = 0
        let newlineUTF16: unichar = 0x0A
        while index < clamped {
            if nsText.character(at: index) == newlineUTF16 {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return (line, clamped - lineStart + 1)
    }

    /// 计算指定行的范围（不含行尾换行符）。
    /// - Parameters:
    ///   - lineNumber: 行号（从 1 开始）
    ///   - text: 文本内容
    /// - Returns: 行内容范围；行号越界（小于 1 或超过总行数）返回 `nil`
    static func rangeOfLine(_ lineNumber: Int, in text: String) -> NSRange? {
        guard lineNumber > 0 else {
            return nil
        }
        let nsText = text as NSString
        var line = 1
        var lineStart = 0
        var index = 0
        let newlineUTF16: unichar = 0x0A
        while index < nsText.length {
            if nsText.character(at: index) == newlineUTF16 {
                if line == lineNumber {
                    return NSRange(location: lineStart, length: index - lineStart)
                }
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        // 末行（无行尾换行符）
        guard line == lineNumber else {
            return nil
        }
        return NSRange(location: lineStart, length: nsText.length - lineStart)
    }

    // MARK: - 布局

    /// 应用自动换行开关对应的 textContainer 宽度跟踪配置。
    private func applyWordWrap() {
        guard let container = textView.textContainer else {
            return
        }
        if isWordWrapEnabled {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width,
                                             height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            scrollView.hasHorizontalScroller = false
        } else {
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
            textView.isHorizontallyResizable = true
            scrollView.hasHorizontalScroller = true
        }
    }

    /// 按 `baseFont × zoomLevel` 应用有效字体。
    private func applyEffectiveFont() {
        let effectiveFont = baseFont.withSize(baseFont.pointSize * CGFloat(storedZoomLevel))
        textView.setEditorFont(effectiveFont)
    }
}

// MARK: - NSTextViewDelegate

extension NPEditorView: NSTextViewDelegate {
    /// 文本变更时通知委托（主线程）。
    /// - Parameter notification: 变更通知
    func textDidChange(_ notification: Notification) {
        delegate?.editorDidChangeContent(self)
    }

    /// 选区变更时通知委托（主线程）。
    /// - Parameter notification: 变更通知
    func textViewDidChangeSelection(_ notification: Notification) {
        delegate?.editorDidChangeSelection(self)
    }
}
