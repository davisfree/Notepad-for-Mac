//
//  NPReplaceControllerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPReplaceController` 替换逻辑测试（覆盖 `05_TEST_PLAN.md` UT-FIND-005 及范围偏移回归）。
final class NPReplaceControllerTests: XCTestCase {

    /// 被测对象（SUT，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var sut: NPReplaceController!

    override func setUp() {
        super.setUp()
        sut = NPReplaceController()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// 单个替换：返回替换后的新文本。
    func testReplacingSingleMatch() {
        let result = sut.replacing(NSRange(location: 6, length: 5), in: "hello world", with: "Notepad")
        XCTAssertEqual(result, "hello Notepad")
    }

    /// 单个替换：无效范围返回原文本。
    func testReplacingInvalidRangeReturnsOriginal() {
        let result = sut.replacing(NSRange(location: 100, length: 5), in: "hello", with: "x")
        XCTAssertEqual(result, "hello")
    }

    /// UT-FIND-005：全部替换返回值 —— 返回 `(text, count)`，count 为实际替换数。
    func testReplacingAllReturnsTextAndCount() {
        let matches = [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3)]
        let (text, count) = sut.replacingAll(matches: matches, in: "abc abc", with: "x")
        XCTAssertEqual(text, "x x")
        XCTAssertEqual(count, 2)
    }

    /// 范围偏移回归：替换为更长内容时，从后往前替换保证所有匹配均被正确替换。
    func testReplacingAllWithLongerReplacementNoOffset() {
        let text = "aa aa aa"
        let matches = [NSRange(location: 0, length: 2), NSRange(location: 3, length: 2), NSRange(location: 6, length: 2)]
        let (result, count) = sut.replacingAll(matches: matches, in: text, with: "bbbbb")
        XCTAssertEqual(result, "bbbbb bbbbb bbbbb")
        XCTAssertEqual(count, 3)
    }

    /// 范围偏移回归：替换为更短内容（含空串删除）时结果同样正确。
    func testReplacingAllWithShorterReplacementNoOffset() {
        let text = "fooXbarXbaz"
        let matches = [NSRange(location: 3, length: 1), NSRange(location: 7, length: 1)]
        let (result, count) = sut.replacingAll(matches: matches, in: text, with: "")
        XCTAssertEqual(result, "foobarbaz")
        XCTAssertEqual(count, 2)
    }

    /// 空匹配列表：返回原文本与 0。
    func testReplacingAllWithEmptyMatches() {
        let (result, count) = sut.replacingAll(matches: [], in: "hello", with: "x")
        XCTAssertEqual(result, "hello")
        XCTAssertEqual(count, 0)
    }
}
