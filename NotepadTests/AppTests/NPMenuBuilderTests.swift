//
//  NPMenuBuilderTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPMenuBuilder` 菜单结构测试（纯数据 spec，无 UI 依赖；结构对齐 PRD 4.1/4.2）。
final class NPMenuBuilderTests: XCTestCase {

    /// 展平菜单结构（含全部子菜单项）。
    private var allSpecs: [NPMenuItemSpec] {
        var result: [NPMenuItemSpec] = []
        var stack = NPMenuBuilder.mainMenuSpecs
        while let spec = stack.popLast() {
            result.append(spec)
            stack.append(contentsOf: spec.children)
        }
        return result
    }

    /// 顶级菜单为 6 个且顺序对齐 PRD 4.1。
    func testTopLevelMenus() {
        XCTAssertEqual(NPMenuBuilder.mainMenuSpecs.map { $0.titleKey },
                       ["Menu.App", "Menu.File", "Menu.Edit", "Menu.Format", "Menu.View", "Menu.Help"])
    }

    /// 所有非分隔线项使用 "Menu.*" 英文 key（03 §2.6）。
    func testAllItemsUseEnglishKeys() {
        for spec in allSpecs where !spec.isSeparator {
            XCTAssertTrue(spec.titleKey.hasPrefix("Menu."), "非法 key：\(spec.titleKey)")
        }
    }

    /// 快捷键映射对齐 PRD 4.2（抽样关键项）。
    func testKeyEquivalents() {
        func spec(_ action: String) -> NPMenuItemSpec? {
            allSpecs.first { $0.actionName == action }
        }
        XCTAssertEqual(spec("newTab:")?.keyEquivalent, "n")
        XCTAssertEqual(spec("newTab:")?.keyModifiers, [.command])
        XCTAssertEqual(spec("newWindow:")?.keyEquivalent, "n")
        XCTAssertEqual(spec("newWindow:")?.keyModifiers, [.shift, .command])
        XCTAssertEqual(spec("saveDocumentAs:")?.keyModifiers, [.shift, .command])
        XCTAssertEqual(spec("showReplaceBarAction:")?.keyModifiers, [.option, .command])
        XCTAssertEqual(spec("goToLineAction:")?.keyModifiers, [.control])
        XCTAssertEqual(spec("toggleWordWrap:")?.keyModifiers, [.option, .command])
        XCTAssertEqual(spec("insertTimestampAction:")?.keyEquivalent, "\u{F708}")
        XCTAssertEqual(spec("insertTimestampAction:")?.keyModifiers, [])
        XCTAssertEqual(spec("toggleStatusBar:")?.keyEquivalent, "/")
    }

    /// 特殊子菜单：服务与"打开最近使用的"带识别 tag。
    func testSpecialSubmenus() {
        XCTAssertTrue(allSpecs.contains { $0.tag == NPConstants.MenuTag.services })
        XCTAssertTrue(allSpecs.contains { $0.tag == NPConstants.MenuTag.recentDocuments })
    }

    /// 勾选状态项携带识别 tag。
    func testStatefulItemsHaveTags() {
        for action in ["toggleWordWrap:", "toggleStatusBar:", "setThemeLight:", "setThemeDark:",
                       "setThemeSystem:", "toggleAlwaysOnTop:"] {
            let spec = allSpecs.first { $0.actionName == action }
            XCTAssertTrue((spec?.tag ?? 0) > 0, "\(action) 缺少 tag")
        }
    }

    /// 帮助菜单："查看帮助"指向 AppDelegate 的应用内帮助窗口（不走 NSApp 默认 showHelp: 无帮助册路径）。
    func testHelpMenuItems() {
        let viewHelp = allSpecs.first { $0.titleKey == "Menu.Help.ViewHelp" }
        XCTAssertEqual(viewHelp?.actionName, "showHelp:")
        XCTAssertEqual(viewHelp?.target, .appDelegate)
        let sendFeedback = allSpecs.first { $0.titleKey == "Menu.Help.SendFeedback" }
        XCTAssertEqual(sendFeedback?.actionName, "sendFeedback:")
        XCTAssertEqual(sendFeedback?.target, .appDelegate)
    }
}
