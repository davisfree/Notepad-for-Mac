//
//  NPGoToLineControllerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPGoToLineController.clampedLineNumber` 行号校验测试（纯函数）。
final class NPGoToLineControllerTests: XCTestCase {

    /// 合法输入原样返回。
    func testValidLineNumber() {
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("5", maxLine: 10), 5)
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("1", maxLine: 10), 1)
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("10", maxLine: 10), 10)
    }

    /// 空白字符修剪。
    func testWhitespaceTrimmed() {
        XCTAssertEqual(NPGoToLineController.clampedLineNumber(" 7 ", maxLine: 10), 7)
    }

    /// 下界夹取：0 与负数夹取到 1。
    func testLowerBoundClamped() {
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("0", maxLine: 10), 1)
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("-3", maxLine: 10), 1)
    }

    /// 上界夹取：越界夹取到 maxLine。
    func testUpperBoundClamped() {
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("99", maxLine: 10), 10)
    }

    /// 非数字输入返回 nil。
    func testNonNumericReturnsNil() {
        XCTAssertNil(NPGoToLineController.clampedLineNumber("abc", maxLine: 10))
        XCTAssertNil(NPGoToLineController.clampedLineNumber("", maxLine: 10))
        XCTAssertNil(NPGoToLineController.clampedLineNumber("12a", maxLine: 10))
        XCTAssertNil(NPGoToLineController.clampedLineNumber("1.5", maxLine: 10))
    }

    /// maxLine 异常（≤ 0）时上限按 1 处理。
    func testDegenerateMaxLine() {
        XCTAssertEqual(NPGoToLineController.clampedLineNumber("3", maxLine: 0), 1)
    }
}
