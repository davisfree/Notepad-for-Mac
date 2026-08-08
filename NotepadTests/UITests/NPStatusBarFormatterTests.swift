//
//  NPStatusBarFormatterTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPStatusBarFormatter` 文案格式化测试（纯函数，对齐 `02_UI_DESIGN.md` 3.3）。
final class NPStatusBarFormatterTests: XCTestCase {

    /// 行列文案：经 `StatusBar.LineCol` 本地化模板格式化（Base 为 "Ln %lld, Col %lld"）。
    func testLineColumnText() {
        let expected = String(format: NSLocalizedString("StatusBar.LineCol", comment: ""), 12, 34)
        XCTAssertEqual(NPStatusBarFormatter.lineColumnText(line: 12, column: 34), expected)
        XCTAssertEqual(NPStatusBarFormatter.lineColumnText(line: 1, column: 1),
                       String(format: NSLocalizedString("StatusBar.LineCol", comment: ""), 1, 1))
    }

    /// 缩放百分比：整数无小数。
    func testZoomText() {
        XCTAssertEqual(NPStatusBarFormatter.zoomText(1.0), "100%")
        XCTAssertEqual(NPStatusBarFormatter.zoomText(1.25), "125%")
        XCTAssertEqual(NPStatusBarFormatter.zoomText(0.1), "10%")
        XCTAssertEqual(NPStatusBarFormatter.zoomText(5.0), "500%")
        XCTAssertEqual(NPStatusBarFormatter.zoomText(1.449), "145%")
    }

    /// 字符数文案：经 `StatusBar.CharacterCount` 本地化模板格式化（Base 为 "%@ characters"，
    /// 与 `testLineColumnText` 同模式——测试进程解析本地化失败时两侧同值仍相等）。
    func testCharacterCountText() {
        XCTAssertEqual(NPStatusBarFormatter.characterCountText(0),
                       String(format: NSLocalizedString("StatusBar.CharacterCount", comment: ""), "0"))
    }

    /// 字符数统计：排除换行符（对齐 Win11 状态栏行为）。
    func testCharacterCountExcludesNewlines() {
        XCTAssertEqual(NPStatusBarFormatter.characterCount(in: ""), 0)
        XCTAssertEqual(NPStatusBarFormatter.characterCount(in: "abc"), 3)
        XCTAssertEqual(NPStatusBarFormatter.characterCount(in: "a\nb\r\nc"), 3)
        XCTAssertEqual(NPStatusBarFormatter.characterCount(in: "\n"), 0)
        XCTAssertEqual(NPStatusBarFormatter.characterCount(in: "换行\n测试"), 4)
    }

    /// 编码显示名：02 §3.3 全清单。
    func testEncodingNames() {
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf8, hasBOM: false), "UTF-8")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf8, hasBOM: true), "UTF-8 BOM")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf16LittleEndian, hasBOM: false), "UTF-16 LE")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf16BigEndian, hasBOM: false), "UTF-16 BE")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf32LittleEndian, hasBOM: false), "UTF-32 LE")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .utf32BigEndian, hasBOM: false), "UTF-32 BE")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .windowsCP1252, hasBOM: false), "ANSI")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .gb18030, hasBOM: false), "GB18030")
        XCTAssertEqual(NPStatusBarFormatter.encodingName(for: .big5, hasBOM: false), "Big5")
    }

    /// 未映射编码回退系统本地化名称（非空）。
    func testEncodingNameFallback() {
        XCTAssertFalse(NPStatusBarFormatter.encodingName(for: .ascii, hasBOM: false).isEmpty)
    }
}
