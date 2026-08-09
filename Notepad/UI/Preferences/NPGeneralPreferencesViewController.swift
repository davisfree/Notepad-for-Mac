//
//  NPGeneralPreferencesViewController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-08.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 偏好设置 - 通用标签页（显示语言 / 主题 / 自动保存 / 显示状态栏）。
///
/// 控件与 `NPPreferences` 双向同步：初始化与 `preferencesDidChange` 通知刷新控件，
/// 控件动作写回偏好（`@Published` didSet 即时持久化）。写回前比对现值，避免
/// 自己写回触发的通知再次写回造成循环。
@MainActor
final class NPGeneralPreferencesViewController: NSViewController {

    // MARK: - 依赖

    /// 偏好存储（测试注入独立 suite 的实例）
    let preferences: NPPreferences

    // MARK: - 控件（internal，供测试断言与驱动动作）

    /// 显示语言弹出菜单
    let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// 主题弹出菜单
    let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    /// 自动保存复选框
    let autoSaveCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    /// 显示状态栏复选框
    let statusBarCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)

    // MARK: - 私有

    /// 表单网格（控件装载后即确定内容尺寸）
    private var grid: NSGridView?
    /// 偏好变更通知观察者令牌
    private var preferencesObserver: NSObjectProtocol?

    // MARK: - 初始化

    /// 创建通用设置页。
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

    /// 显示语言变更：经共享逻辑写偏好 + AppleLanguages，并提示重启后生效。
    /// - Parameter sender: 弹出菜单
    @objc func languageDidChange(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let language = NPLanguage(rawValue: raw) else {
            return
        }
        NPLanguage.apply(language, to: preferences, window: view.window)
    }

    /// 主题变更：正式路径经 `NPThemeManager` 立即应用外观并写偏好；
    /// 测试注入独立偏好时仅写该实例，不触碰全局外观。
    /// - Parameter sender: 弹出菜单
    @objc func themeDidChange(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let theme = NPTheme(rawValue: raw) else {
            return
        }
        guard preferences.theme != theme else {
            return
        }
        if preferences === NPPreferences.shared {
            NPThemeManager.shared.apply(theme: theme)
        } else {
            preferences.theme = theme
        }
    }

    /// 自动保存开关。
    /// - Parameter sender: 复选框
    @objc func autoSaveDidChange(_ sender: NSButton) {
        let enabled = sender.state == .on
        guard preferences.isAutoSaveEnabled != enabled else {
            return
        }
        preferences.isAutoSaveEnabled = enabled
    }

    /// 显示状态栏开关。
    /// - Parameter sender: 复选框
    @objc func statusBarDidChange(_ sender: NSButton) {
        let visible = sender.state == .on
        guard preferences.isStatusBarVisible != visible else {
            return
        }
        preferences.isStatusBarVisible = visible
    }

    // MARK: - 私有

    /// 装配控件内容与动作。
    private func configureControls() {
        for language in NPLanguage.allCases {
            languagePopup.addItem(withTitle: language.displayName)
            languagePopup.lastItem?.representedObject = language.rawValue
        }
        languagePopup.target = self
        languagePopup.action = #selector(languageDidChange(_:))

        for theme in NPTheme.allCases {
            themePopup.addItem(withTitle: theme.displayName)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        themePopup.target = self
        themePopup.action = #selector(themeDidChange(_:))

        autoSaveCheckbox.title = Self.localized("Preferences.General.AutoSave", comment: "通用：自动保存")
        autoSaveCheckbox.target = self
        autoSaveCheckbox.action = #selector(autoSaveDidChange(_:))

        statusBarCheckbox.title = Self.localized("Preferences.General.ShowStatusBar", comment: "通用：显示状态栏")
        statusBarCheckbox.target = self
        statusBarCheckbox.action = #selector(statusBarDidChange(_:))
    }

    /// 行式表单布局：左列标签右对齐，右列控件。
    private func layoutForm() {
        let grid = NSGridView(views: [
            [Self.makeLabel(Self.localized("Preferences.General.DisplayLanguage",
                                           comment: "通用：显示语言")), languagePopup],
            [Self.makeLabel(Self.localized("Preferences.General.Theme",
                                           comment: "通用：主题")), themePopup],
            [NSGridCell.emptyContentView, autoSaveCheckbox],
            [NSGridCell.emptyContentView, statusBarCheckbox],
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
            languagePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            themePopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        self.grid = grid
    }

    /// 读偏好刷新全部控件。
    private func refreshFromPreferences() {
        selectPopupItem(languagePopup, rawValue: preferences.displayLanguage.rawValue)
        selectPopupItem(themePopup, rawValue: preferences.theme.rawValue)
        autoSaveCheckbox.state = preferences.isAutoSaveEnabled ? .on : .off
        statusBarCheckbox.state = preferences.isStatusBarVisible ? .on : .off
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

    /// 按 representedObject（rawValue）选中弹出菜单项。
    /// - Parameters:
    ///   - popup: 弹出菜单
    ///   - rawValue: 目标项 representedObject 字符串
    private func selectPopupItem(_ popup: NSPopUpButton, rawValue: String) {
        let index = popup.itemArray.firstIndex { $0.representedObject as? String == rawValue }
        popup.selectItem(at: index ?? 0)
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
