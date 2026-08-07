//
//  NPEditorViewTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPEditorView` 行列计算纯函数测试（无 UI 依赖，静态方法可直接单测）。
final class NPEditorViewTests: XCTestCase {

    /// 行列计算：首行首列从 1 开始。
    func testLineAndColumnAtStart() {
        let result = NPEditorView.lineAndColumn(at: 0, in: "Hello\nWorld")
        XCTAssertEqual(result.line, 1)
        XCTAssertEqual(result.column, 1)
    }

    /// 行列计算：换行符后进入下一行第一列。
    func testLineAndColumnAfterNewline() {
        // "Hello\nWorld"：偏移 6 为 'W'
        let result = NPEditorView.lineAndColumn(at: 6, in: "Hello\nWorld")
        XCTAssertEqual(result.line, 2)
        XCTAssertEqual(result.column, 1)
    }

    /// 行列计算：行中间位置列号正确。
    func testLineAndColumnMiddleOfLine() {
        let result = NPEditorView.lineAndColumn(at: 8, in: "Hello\nWorld")
        XCTAssertEqual(result.line, 2)
        XCTAssertEqual(result.column, 3)
    }

    /// 行列计算：偏移越界自动夹取到文本末尾。
    func testLineAndColumnClampsOutOfBoundsLocation() {
        let result = NPEditorView.lineAndColumn(at: 100, in: "ab\ncd")
        XCTAssertEqual(result.line, 2)
        XCTAssertEqual(result.column, 3)
    }

    /// 行列计算：中文等多字节字符按 UTF-16 偏移计数。
    func testLineAndColumnWithUnicode() {
        // "你好\n世界"：偏移 3 为 '世'
        let result = NPEditorView.lineAndColumn(at: 3, in: "你好\n世界")
        XCTAssertEqual(result.line, 2)
        XCTAssertEqual(result.column, 1)
    }

    /// 行范围：取中间行内容（不含行尾换行符）。
    func testRangeOfMiddleLine() {
        let range = NPEditorView.rangeOfLine(2, in: "one\ntwo\nthree")
        XCTAssertEqual(range, NSRange(location: 4, length: 3))
    }

    /// 行范围：末行无行尾换行符。
    func testRangeOfLastLine() {
        let range = NPEditorView.rangeOfLine(3, in: "one\ntwo\nthree")
        XCTAssertEqual(range, NSRange(location: 8, length: 5))
    }

    /// 行范围：行号越界返回 nil。
    func testRangeOfLineOutOfBounds() {
        XCTAssertNil(NPEditorView.rangeOfLine(0, in: "one"))
        XCTAssertNil(NPEditorView.rangeOfLine(5, in: "one\ntwo"))
    }
}
