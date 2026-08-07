//
//  NPMenuBuilder.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 菜单动作目标类别。
enum NPMenuTarget {
    /// nil target，走响应链（`NSTextView` / `NPEditorView` / `NSDocument` / `NSWindow` 等）
    case responderChain
    /// `NSApplication.shared`
    case application
    /// `AppDelegate`（应用级动作与占位钩子）
    case appDelegate
}

/// 菜单项结构描述（纯数据，可无 UI 测试）。
struct NPMenuItemSpec {
    /// `NSLocalizedString` key（"Menu.Section.Name" 形式；分隔线为空串）
    let titleKey: String
    /// 快捷键字符（F5 等功能键使用 `U+F704+` 私有区标量）
    let keyEquivalent: String
    /// 快捷键修饰键
    let keyModifiers: NSEvent.ModifierFlags
    /// 动作选择器字符串（空串 = 无动作，如子菜单容器）
    let actionName: String
    /// 动作目标类别
    let target: NPMenuTarget
    /// 菜单项 tag（`NPConstants.MenuTag`，无需识别时为 0）
    let tag: Int
    /// 子菜单项
    let children: [NPMenuItemSpec]
    /// 是否为分隔线
    let isSeparator: Bool

    /// 创建普通菜单项描述。
    init(titleKey: String,
         keyEquivalent: String = "",
         keyModifiers: NSEvent.ModifierFlags = [.command],
         actionName: String = "",
         target: NPMenuTarget = .responderChain,
         tag: Int = 0,
         children: [NPMenuItemSpec] = []) {
        self.titleKey = titleKey
        self.keyEquivalent = keyEquivalent
        self.keyModifiers = keyModifiers
        self.actionName = actionName
        self.target = target
        self.tag = tag
        self.children = children
        self.isSeparator = false
    }

    private init(separator: Void) {
        self.titleKey = ""
        self.keyEquivalent = ""
        self.keyModifiers = []
        self.actionName = ""
        self.target = .responderChain
        self.tag = 0
        self.children = []
        self.isSeparator = true
    }

    /// 分隔线描述。
    static let separator = NPMenuItemSpec(separator: ())
}

/// 主菜单构建器（App 层）。
///
/// 菜单结构按 `PRD_Notepad_macOS.md` 4.1 全量复刻、快捷键按 4.2 映射，
/// 以 `NPMenuItemSpec` 纯数据描述（可无 UI 验证结构），再由本类装配为 `NSMenu`。
@MainActor
enum NPMenuBuilder {

    // MARK: - 构建

    /// 构建完整主菜单。
    /// - Returns: 主菜单（含应用菜单与全部子菜单；服务菜单已注册到 `NSApp.servicesMenu`）
    static func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        for spec in mainMenuSpecs {
            mainMenu.addItem(buildItem(from: spec))
        }
        return mainMenu
    }

    /// 由结构描述装配菜单项（递归处理子菜单）。
    /// - Parameter spec: 菜单项结构描述
    /// - Returns: 菜单项
    private static func buildItem(from spec: NPMenuItemSpec) -> NSMenuItem {
        if spec.isSeparator {
            return NSMenuItem.separator()
        }
        let item = NSMenuItem(
            title: spec.titleKey.isEmpty ? "" : NSLocalizedString(spec.titleKey, comment: "菜单：\(spec.titleKey)"),
            action: spec.actionName.isEmpty ? nil : Selector(spec.actionName),
            keyEquivalent: spec.keyEquivalent
        )
        item.keyEquivalentModifierMask = spec.keyModifiers
        item.tag = spec.tag
        switch spec.target {
        case .responderChain:
            break // nil target，走响应链
        case .application:
            item.target = NSApp
        case .appDelegate:
            item.target = NSApp.delegate
        }
        // 子菜单容器：服务菜单与"打开最近使用的"为特殊子菜单，其余按 children 递归
        if spec.tag == NPConstants.MenuTag.services {
            let servicesMenu = NSMenu(title: item.title)
            item.submenu = servicesMenu
            NSApp.servicesMenu = servicesMenu
        } else if spec.tag == NPConstants.MenuTag.recentDocuments || !spec.children.isEmpty {
            let submenu = NSMenu(title: item.title)
            for child in spec.children {
                submenu.addItem(buildItem(from: child))
            }
            if spec.tag == NPConstants.MenuTag.recentDocuments {
                // 最近文件列表由 AppDelegate（NSMenuDelegate）在菜单展开时动态重建
                submenu.identifier = NSUserInterfaceItemIdentifier(NPConstants.recentDocumentsMenuIdentifier)
                submenu.delegate = NSApp.delegate as? NSMenuDelegate
            }
            item.submenu = submenu
        }
        return item
    }

    // MARK: - 菜单结构（PRD 4.1 / 4.2）

    /// 主菜单结构（自上而下：Notepad / 文件 / 编辑 / 格式 / 视图 / 帮助）。
    static let mainMenuSpecs: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.App", children: appMenuChildren),
        NPMenuItemSpec(titleKey: "Menu.File", children: fileMenuChildren),
        NPMenuItemSpec(titleKey: "Menu.Edit", children: editMenuChildren),
        NPMenuItemSpec(titleKey: "Menu.Format", children: formatMenuChildren),
        NPMenuItemSpec(titleKey: "Menu.View", children: viewMenuChildren),
        NPMenuItemSpec(titleKey: "Menu.Help", children: helpMenuChildren),
    ]

    /// Notepad 应用菜单（"检查更新…"仅直发/Homebrew 构建，03 §2.4）。
    private static let appMenuChildren: [NPMenuItemSpec] = {
        var items: [NPMenuItemSpec] = [
            NPMenuItemSpec(titleKey: "Menu.App.About", actionName: "orderFrontStandardAboutPanel:", target: .application),
        ]
        #if !APP_STORE
        items.append(NPMenuItemSpec(titleKey: "Menu.App.CheckUpdates", actionName: "checkForUpdates:", target: .appDelegate))
        #endif
        items.append(contentsOf: [
            NPMenuItemSpec(titleKey: "Menu.App.Preferences", keyEquivalent: ",", actionName: "showPreferences:",
                           target: .appDelegate),
            .separator,
            NPMenuItemSpec(titleKey: "Menu.App.Services", tag: NPConstants.MenuTag.services),
            .separator,
            NPMenuItemSpec(titleKey: "Menu.App.Hide", keyEquivalent: "h", actionName: "hide:", target: .application),
            NPMenuItemSpec(titleKey: "Menu.App.HideOthers", keyEquivalent: "h", keyModifiers: [.option, .command],
                           actionName: "hideOtherApplications:", target: .application),
            NPMenuItemSpec(titleKey: "Menu.App.ShowAll", actionName: "unhideAllApplications:", target: .application),
            .separator,
            NPMenuItemSpec(titleKey: "Menu.App.Quit", keyEquivalent: "q", actionName: "terminate:", target: .application),
        ])
        return items
    }()

    /// 文件菜单。
    private static let fileMenuChildren: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.File.NewTab", keyEquivalent: "n", actionName: "newTab:", target: .appDelegate),
        NPMenuItemSpec(titleKey: "Menu.File.NewWindow", keyEquivalent: "n", keyModifiers: [.shift, .command],
                       actionName: "newWindow:", target: .appDelegate),
        NPMenuItemSpec(titleKey: "Menu.File.Open", keyEquivalent: "o", actionName: "openDocumentAction:",
                       target: .appDelegate),
        NPMenuItemSpec(titleKey: "Menu.File.OpenRecent", tag: NPConstants.MenuTag.recentDocuments, children: [
            NPMenuItemSpec(titleKey: "Menu.File.ClearRecent", actionName: "clearRecentDocuments:", target: .appDelegate),
        ]),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.File.Save", keyEquivalent: "s", actionName: "saveDocument:"),
        NPMenuItemSpec(titleKey: "Menu.File.SaveAs", keyEquivalent: "s", keyModifiers: [.shift, .command],
                       actionName: "saveDocumentAs:"),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.File.PageSetup", keyModifiers: [], actionName: "showPageSetupAction:",
                       target: .appDelegate),
        NPMenuItemSpec(titleKey: "Menu.File.Print", keyEquivalent: "p", actionName: "printDocumentAction:",
                       target: .appDelegate),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.File.CloseTab", keyEquivalent: "w", actionName: "closeCurrentTab:"),
        NPMenuItemSpec(titleKey: "Menu.File.CloseWindow", keyEquivalent: "w", keyModifiers: [.shift, .command],
                       actionName: "closeWindowAction:"),
    ]

    /// 编辑菜单。
    private static let editMenuChildren: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.Edit.Undo", keyEquivalent: "z", actionName: "undo:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.Redo", keyEquivalent: "z", keyModifiers: [.shift, .command],
                       actionName: "redo:"),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.Edit.Cut", keyEquivalent: "x", actionName: "cut:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.Copy", keyEquivalent: "c", actionName: "copy:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.Paste", keyEquivalent: "v", actionName: "paste:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.Delete", keyModifiers: [], actionName: "delete:"),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.Edit.SelectAll", keyEquivalent: "a", actionName: "selectAll:"),
        // F5 功能键（NSF5FunctionKey = U+F708），无修饰键，对齐 Win11 时间/日期
        NPMenuItemSpec(titleKey: "Menu.Edit.InsertTimestamp", keyEquivalent: "\u{F708}", keyModifiers: [],
                       actionName: "insertTimestampAction:"),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.Edit.Find", keyEquivalent: "f", actionName: "showFindBarAction:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.FindNext", keyEquivalent: "g", actionName: "findNextAction:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.FindPrevious", keyEquivalent: "g", keyModifiers: [.shift, .command],
                       actionName: "findPreviousAction:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.Replace", keyEquivalent: "f", keyModifiers: [.option, .command],
                       actionName: "showReplaceBarAction:"),
        NPMenuItemSpec(titleKey: "Menu.Edit.GoToLine", keyEquivalent: "g", keyModifiers: [.control],
                       actionName: "goToLineAction:"),
    ]

    /// 格式菜单。
    private static let formatMenuChildren: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.Format.WordWrap", keyEquivalent: "w", keyModifiers: [.option, .command],
                       actionName: "toggleWordWrap:", tag: NPConstants.MenuTag.wordWrap),
        .separator,
        // 字体…无快捷键，与 Win11 原版一致
        NPMenuItemSpec(titleKey: "Menu.Format.Font", keyModifiers: [], actionName: "showFontPanel:", target: .appDelegate),
    ]

    /// 视图菜单。
    private static let viewMenuChildren: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.View.Zoom", children: [
            NPMenuItemSpec(titleKey: "Menu.View.ZoomIn", keyEquivalent: "+", actionName: "zoomInAction:"),
            NPMenuItemSpec(titleKey: "Menu.View.ZoomOut", keyEquivalent: "-", actionName: "zoomOutAction:"),
            NPMenuItemSpec(titleKey: "Menu.View.ZoomReset", keyEquivalent: "0", actionName: "resetZoomAction:"),
        ]),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.View.NextTab", keyEquivalent: "]", keyModifiers: [.shift, .command],
                       actionName: "selectNextTab:"),
        NPMenuItemSpec(titleKey: "Menu.View.PreviousTab", keyEquivalent: "[", keyModifiers: [.shift, .command],
                       actionName: "selectPreviousTab:"),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.View.StatusBar", keyEquivalent: "/", actionName: "toggleStatusBar:",
                       target: .appDelegate, tag: NPConstants.MenuTag.statusBar),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.View.Theme", children: [
            NPMenuItemSpec(titleKey: "Menu.View.ThemeLight", actionName: "setThemeLight:", target: .appDelegate,
                           tag: NPConstants.MenuTag.themeLight),
            NPMenuItemSpec(titleKey: "Menu.View.ThemeDark", actionName: "setThemeDark:", target: .appDelegate,
                           tag: NPConstants.MenuTag.themeDark),
            NPMenuItemSpec(titleKey: "Menu.View.ThemeSystem", actionName: "setThemeSystem:", target: .appDelegate,
                           tag: NPConstants.MenuTag.themeSystem),
        ]),
        .separator,
        NPMenuItemSpec(titleKey: "Menu.View.AlwaysOnTop", actionName: "toggleAlwaysOnTop:", target: .appDelegate,
                       tag: NPConstants.MenuTag.alwaysOnTop),
    ]

    /// 帮助菜单。
    private static let helpMenuChildren: [NPMenuItemSpec] = [
        NPMenuItemSpec(titleKey: "Menu.Help.ViewHelp", actionName: "showHelp:", target: .application),
        NPMenuItemSpec(titleKey: "Menu.Help.SendFeedback", actionName: "sendFeedback:", target: .appDelegate),
    ]
}
