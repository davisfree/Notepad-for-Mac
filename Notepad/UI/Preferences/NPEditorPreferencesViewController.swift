//
//  NPEditorPreferencesViewController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-08.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 偏好设置 - 编辑器标签页（字体 / 自动换行 / 默认编码 / 默认换行符 / 默认缩放）。
///
/// 编码清单与显示名复用 `NPEncodingManager` + `NPStatusBarFormatter`（与状态栏一致）；
/// 缩放档位与状态栏缩放菜单一致（PRD 4.3）。
@MainActor
final class NPEditorPreferencesViewController: NSViewController {

    // MARK: - 常量

    /// 缩放预设（与状态栏缩放菜单档位一致，均在合法范围 0.1–5.0 内）
    static let zoomPresets: [(title: String, value: Double)] = [
        ("100%", 1.0),
        ("125%", 1.25),
        ("150%", 1.5),
        ("200%", 2.0)
    ]

    /// 缩放预设匹配容差（浮点比较）
    private static let zoomMatchTolerance = 0.001

    // MARK: - 依赖

    /// 偏好存储（测试注入独立 suite 的实例）
    let preferences: NPPreferences

    // MARK: - 控件（internal，供测试断言与驱动动作）

    /// 当前字体名 + 字号（只读展示）
    let fontTextField = NSTextField(labelWithString: "")
    /// "选择…"按钮（打开系统字体面板）
    let chooseFontButton = NSButton(title: "", target: nil, action: nil)
    /// 自动换行复选框
    let wordWrapCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    /// 默认编码弹出菜单
    let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// 默认换行符弹出菜单
    let lineEndingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// 默认缩放弹出菜单
    let zoomPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // MARK: - 私有

    /// 表单网格（控件装载后即确定内容尺寸）
    private var grid: NSGridView?
    /// 偏好变更通知观察者令牌
    private var preferencesObserver: NSObjectProtocol?
    /// 字体面板关闭观察者令牌（关闭后恢复 `NSFontManager.target` 为响应链投递）
    private var fontPanelCloseObserver: NSObjectProtocol?

    // MARK: - 初始化

    /// 创建编辑器设置页。
    /// - Parameter preferences: 偏好存储（默认单例）
    init(preferences: NPPreferences = .shared) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("本工程不使用 nib/storyboard（纯代码布局）")
    }

    deinit {
        if let preferencesObserver {
            NotificationCenter.default.removeObserver(preferencesObserver)
        }
        if let fontPanelCloseObserver {
            NotificationCenter.default.removeObserver(fontPanelCloseObserver)
        }
    }

    // MARK: - 视图装配

    override func loadView() {
        view = NSView(frame: .zero)
        configureControls()
        layoutForm()
        refreshFromPreferences()
        observePreferences()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 工具栏样式 NSTabViewController 按各页 preferredContentSize 调整窗口尺寸
        view.layoutSubtreeIfNeeded()
        let contentHeight = grid?.fittingSize.height ?? 0
        preferredContentSize = NSSize(width: 420, height: contentHeight + 40)
    }

    // MARK: - 控件动作

    /// "选择…"：打开系统字体面板（选择结果经 `NSFontManager.target` 回传）。
    /// - Parameter sender: 按钮
    @objc func chooseFont(_ sender: Any?) {
        let fontManager = NSFontManager.shared
        fontManager.setSelectedFont(preferences.font, isMultiple: false)
        // 显式指定回传目标：本页视图直接挂在容器视图上（非 childVC），不在窗口
        // 响应链中；字体面板作为 key 窗口发出的 changeFont: 沿响应链到不了本页，
        // 导致选择结果丢失（偏好字体不更新、字体名展示不刷新）。
        fontManager.target = self
        // 面板关闭后恢复响应链投递，避免影响"格式 → 字体…"路径（该路径依赖
        // NPTextView 沿响应链接收 changeFont:）
        if fontPanelCloseObserver == nil {
            fontPanelCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: NSFontPanel.shared,
                queue: nil
            ) { _ in
                Task { @MainActor in
                    NSFontManager.shared.target = nil
                }
            }
        }
        fontManager.orderFrontFontPanel(sender)
    }

    /// 字体面板回传（`NSFontManager.target` 消息）：把面板选择写回偏好。
    /// 偏好变更通知触发字体名展示刷新与已开窗口字体同步。
    /// - Parameter sender: 字体管理器
    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else {
            return
        }
        let newFont = fontManager.convert(preferences.font)
        guard newFont.fontName != preferences.font.fontName
                || newFont.pointSize != preferences.font.pointSize else {
            return
        }
        preferences.font = newFont
    }

    /// 自动换行开关。
    /// - Parameter sender: 复选框
    @objc func wordWrapDidChange(_ sender: NSButton) {
        let enabled = sender.state == .on
        guard preferences.isWordWrapEnabled != enabled else {
            return
        }
        preferences.isWordWrapEnabled = enabled
    }

    /// 默认编码变更。
    /// - Parameter sender: 弹出菜单
    @objc func encodingDidChange(_ sender: NSPopUpButton) {
        guard let raw = (sender.selectedItem?.representedObject as? NSNumber)?.uintValue else {
            return
        }
        let encoding = String.Encoding(rawValue: raw)
        guard preferences.defaultEncoding != encoding else {
            return
        }
        preferences.defaultEncoding = encoding
    }

    /// 默认换行符变更。
    /// - Parameter sender: 弹出菜单
    @objc func lineEndingDidChange(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let lineEnding = NPLineEnding(rawValue: raw) else {
            return
        }
        guard preferences.defaultLineEnding != lineEnding else {
            return
        }
        preferences.defaultLineEnding = lineEnding
    }

    /// 默认缩放变更（写回前钳制到合法范围 0.1–5.0）。
    /// - Parameter sender: 弹出菜单
    @objc func zoomDidChange(_ sender: NSPopUpButton) {
        guard let value = (sender.selectedItem?.representedObject as? NSNumber)?.doubleValue else {
            return
        }
        let zoom = min(max(value, 0.1), 5.0)
        guard preferences.defaultZoomLevel != zoom else {
            return
        }
        preferences.defaultZoomLevel = zoom
    }

    // MARK: - 私有

    /// 装配控件内容与动作。
    private func configureControls() {
        chooseFontButton.title = Self.localized("Preferences.Editor.ChooseFont", comment: "编辑器：选择字体按钮")
        chooseFontButton.bezelStyle = .rounded
        chooseFontButton.target = self
        chooseFontButton.action = #selector(chooseFont(_:))

        wordWrapCheckbox.title = Self.localized("Preferences.Editor.WordWrap", comment: "编辑器：自动换行")
        wordWrapCheckbox.target = self
        wordWrapCheckbox.action = #selector(wordWrapDidChange(_:))

        for encoding in NPEncodingManager.supportedEncodings {
            encodingPopup.addItem(withTitle: NPStatusBarFormatter.encodingName(for: encoding, hasBOM: false))
            encodingPopup.lastItem?.representedObject = NSNumber(value: encoding.rawValue)
        }
        encodingPopup.target = self
        encodingPopup.action = #selector(encodingDidChange(_:))

        for lineEnding in NPLineEnding.allCases {
            lineEndingPopup.addItem(withTitle: lineEnding.displayName)
            lineEndingPopup.lastItem?.representedObject = lineEnding.rawValue
        }
        lineEndingPopup.target = self
        lineEndingPopup.action = #selector(lineEndingDidChange(_:))

        for preset in Self.zoomPresets {
            zoomPopup.addItem(withTitle: preset.title)
            zoomPopup.lastItem?.representedObject = NSNumber(value: preset.value)
        }
        zoomPopup.target = self
        zoomPopup.action = #selector(zoomDidChange(_:))
    }

    /// 行式表单布局：左列标签右对齐，右列控件（字体行为"当前字体 + 选择按钮"）。
    private func layoutForm() {
        let fontRow = NSStackView(views: [fontTextField, chooseFontButton])
        fontRow.orientation = .horizontal
        fontRow.spacing = 8
        fontRow.alignment = .centerY

        let grid = NSGridView(views: [
            [Self.makeLabel(Self.localized("Preferences.Font", comment: "编辑器：字体")), fontRow],
            [NSGridCell.emptyContentView, wordWrapCheckbox],
            [Self.makeLabel(Self.localized("Preferences.Editor.DefaultEncoding",
                                           comment: "编辑器：默认编码")), encodingPopup],
            [Self.makeLabel(Self.localized("Preferences.Editor.DefaultLineEnding",
                                           comment: "编辑器：默认换行符")), lineEndingPopup],
            [Self.makeLabel(Self.localized("Preferences.Editor.DefaultZoom",
                                           comment: "编辑器：默认缩放")), zoomPopup]
        ])
        grid.column(at: 0).xPlacement = .trailing
        // 逐行垂直居中：默认基线对齐会让标签相对右侧控件偏高
        for index in 0..<grid.numberOfRows {
            grid.row(at: index).yPlacement = .center
        }
        grid.columnSpacing = 8
        grid.rowSpacing = 12
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
            encodingPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            lineEndingPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            zoomPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
        self.grid = grid
    }

    /// 读偏好刷新全部控件。
    private func refreshFromPreferences() {
        fontTextField.stringValue = Self.fontDescription(preferences.font)
        wordWrapCheckbox.state = preferences.isWordWrapEnabled ? .on : .off
        selectPopupItem(encodingPopup, rawValue: NSNumber(value: preferences.defaultEncoding.rawValue))
        selectPopupItem(lineEndingPopup, rawValue: preferences.defaultLineEnding.rawValue)
        refreshZoomSelection()
    }

    /// 刷新缩放选中项：命中预设则选中；非预设值（如微调后的档位）追加临时项显示当前百分比。
    private func refreshZoomSelection() {
        while zoomPopup.numberOfItems > Self.zoomPresets.count {
            zoomPopup.removeItem(at: zoomPopup.numberOfItems - 1)
        }
        let zoom = preferences.defaultZoomLevel
        if let index = Self.zoomPresets.firstIndex(where: {
            abs($0.value - zoom) < Self.zoomMatchTolerance
        }) {
            zoomPopup.selectItem(at: index)
        } else {
            let percent = Int((zoom * 100).rounded())
            zoomPopup.addItem(withTitle: "\(percent)%")
            zoomPopup.lastItem?.representedObject = NSNumber(value: zoom)
            zoomPopup.selectItem(at: zoomPopup.numberOfItems - 1)
        }
    }

    /// 订阅偏好变更（覆盖"全部恢复默认"等面板外修改路径）。
    private func observePreferences() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: NPNotificationNames.preferencesDidChange,
            object: preferences,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromPreferences()
            }
        }
    }

    /// 按 representedObject 选中弹出菜单项。
    /// - Parameters:
    ///   - popup: 弹出菜单
    ///   - rawValue: 目标项 representedObject（字符串或编码 NSNumber）
    private func selectPopupItem(_ popup: NSPopUpButton, rawValue: Any) {
        let index = popup.itemArray.firstIndex { item in
            switch (item.representedObject, rawValue) {
            case let (lhs as String, rhs as String):
                return lhs == rhs
            case let (lhs as NSNumber, rhs as NSNumber):
                return lhs == rhs
            default:
                return false
            }
        }
        popup.selectItem(at: index ?? 0)
    }

    /// 字体展示文案（字体名 + 字号，字号去尾零）。
    /// - Parameter font: 字体
    /// - Returns: 展示文案
    private static func fontDescription(_ font: NSFont) -> String {
        let name = font.displayName ?? font.fontName
        let size = font.pointSize
        let sizeText = size.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(size))
            : String(format: "%.1f", size)
        return "\(name) \(sizeText)"
    }

    /// 表单标签（右对齐，附冒号）。
    /// - Parameter text: 标签文本
    /// - Returns: 标签
    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text + ":")
        label.alignment = .right
        return label
    }

    /// 读取 Preferences.strings 本地化文案。
    /// - Parameters:
    ///   - key: 本地化 key
    ///   - comment: 注释
    /// - Returns: 本地化文案
    static func localized(_ key: String, comment: String) -> String {
        NSLocalizedString(key, tableName: "Preferences", comment: comment)
    }
}
