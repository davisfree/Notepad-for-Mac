//
//  NPTouchBarSupport.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// Touch Bar 支持（PRD FR-023；NSTouchBar 自 macOS 10.12.2 可用，无 Touch Bar 的设备不显示）。
///
/// 默认项：新建 / 打开 / 保存 / 查找 / 自动换行开关（复用现有菜单 action）；
/// 编辑上下文项：剪切 / 复制 / 粘贴 / 撤销 / 重做（响应链 action）。
/// 实现为 `NPEditorWindowController` 扩展：窗口控制器作 `NSTouchBarDelegate`。
extension NPEditorWindowController: NSTouchBarDelegate {

    // MARK: - 标识

    /// Touch Bar 项标识。
    private enum TouchBarIdentifier {
        static let new = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.new")
        static let open = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.open")
        static let save = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.save")
        static let find = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.find")
        static let wordWrap = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.wordWrap")
        static let cut = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.cut")
        static let copy = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.copy")
        static let paste = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.paste")
        static let undo = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.undo")
        static let redo = NSTouchBarItem.Identifier("com.notepadmac.Notepad.touchbar.redo")
    }

    /// 默认项标识顺序（FR-023 默认五项 + 编辑上下文五项）。
    private static let defaultIdentifiers: [NSTouchBarItem.Identifier] = [
        TouchBarIdentifier.new,
        TouchBarIdentifier.open,
        TouchBarIdentifier.save,
        TouchBarIdentifier.find,
        TouchBarIdentifier.wordWrap,
        TouchBarIdentifier.cut,
        TouchBarIdentifier.copy,
        TouchBarIdentifier.paste,
        TouchBarIdentifier.undo,
        TouchBarIdentifier.redo
    ]

    // MARK: - 装配

    /// 安装 Touch Bar（窗口控制器初始化时调用）。
    func installTouchBar() {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = Self.defaultIdentifiers
        self.touchBar = touchBar
    }

    /// 按需创建 Touch Bar 项。
    /// - Parameters:
    ///   - touchBar: Touch Bar
    ///   - identifier: 项标识
    /// - Returns: Touch Bar 项
    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case TouchBarIdentifier.new:
            return makeButtonItem(identifier, symbol: "doc.badge.plus", accessibilityKey: "Menu.File.NewWindow",
                                  action: #selector(AppDelegate.newWindow(_:)))
        case TouchBarIdentifier.open:
            return makeButtonItem(identifier, symbol: "folder", accessibilityKey: "Menu.File.Open",
                                  action: #selector(AppDelegate.openDocumentAction(_:)))
        case TouchBarIdentifier.save:
            return makeButtonItem(identifier, symbol: "square.and.arrow.down", accessibilityKey: "Menu.File.Save",
                                  action: NSSelectorFromString("saveDocument:"))
        case TouchBarIdentifier.find:
            return makeButtonItem(identifier, symbol: "magnifyingglass", accessibilityKey: "Menu.Edit.Find",
                                  action: #selector(NPEditorView.showFindBarAction(_:)))
        case TouchBarIdentifier.wordWrap:
            return makeButtonItem(identifier, symbol: "text.alignleft", accessibilityKey: "Menu.Format.WordWrap",
                                  action: #selector(NPEditorView.toggleWordWrap(_:)))
        case TouchBarIdentifier.cut:
            return makeButtonItem(identifier, symbol: "scissors", accessibilityKey: "Menu.Edit.Cut",
                                  action: NSSelectorFromString("cut:"))
        case TouchBarIdentifier.copy:
            return makeButtonItem(identifier, symbol: "doc.on.doc", accessibilityKey: "Menu.Edit.Copy",
                                  action: NSSelectorFromString("copy:"))
        case TouchBarIdentifier.paste:
            return makeButtonItem(identifier, symbol: "doc.on.clipboard", accessibilityKey: "Menu.Edit.Paste",
                                  action: NSSelectorFromString("paste:"))
        case TouchBarIdentifier.undo:
            return makeButtonItem(identifier, symbol: "arrow.uturn.backward", accessibilityKey: "Menu.Edit.Undo",
                                  action: NSSelectorFromString("undo:"))
        case TouchBarIdentifier.redo:
            return makeButtonItem(identifier, symbol: "arrow.uturn.forward", accessibilityKey: "Menu.Edit.Redo",
                                  action: NSSelectorFromString("redo:"))
        default:
            return nil
        }
    }

    /// 创建图标按钮项（target 为 nil 走响应链；动作与菜单项同一 selector）。
    /// - Parameters:
    ///   - identifier: 项标识
    ///   - symbol: SF Symbol 名称
    ///   - accessibilityKey: 无障碍标签本地化 key
    ///   - action: 动作（复用菜单 action）
    /// - Returns: Touch Bar 项
    private func makeButtonItem(_ identifier: NSTouchBarItem.Identifier, symbol: String,
                                accessibilityKey: String, action: Selector) -> NSTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: identifier)
        let accessibilityLabel = NSLocalizedString(accessibilityKey, comment: "Touch Bar 按钮")
        let button: NSButton
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityLabel) {
            button = NSButton(image: image, target: nil, action: action)
        } else {
            button = NSButton(title: accessibilityLabel, target: nil, action: action)
        }
        button.setAccessibilityLabel(accessibilityLabel)
        item.view = button
        return item
    }
}
