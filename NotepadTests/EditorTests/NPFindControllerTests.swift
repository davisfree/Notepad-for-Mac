//
//  NPFindControllerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPFindController` 查找逻辑测试（覆盖 `05_TEST_PLAN.md` UT-FIND-001 ~ UT-FIND-006）。
final class NPFindControllerTests: XCTestCase {

    /// 被测对象（SUT，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var sut: NPFindController!

    override func setUp() {
        super.setUp()
        sut = NPFindController()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// UT-FIND-001：默认不区分大小写 —— 未设置 `caseSensitive`，查找 "test" 命中 "Test"/"TEST" 等。
    func testDefaultCaseInsensitive() throws {
        let matches = try sut.allMatches(in: "Test test TEST tesT", query: "test", options: [])
        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(matches[0], NSRange(location: 0, length: 4))
    }

    /// UT-FIND-002：区分大小写 —— 设置 `caseSensitive` 后仅命中完全匹配的 "test"。
    func testCaseSensitive() throws {
        let matches = try sut.allMatches(in: "Test test TEST", query: "test", options: [.caseSensitive])
        XCTAssertEqual(matches, [NSRange(location: 5, length: 4)])
    }

    /// UT-FIND-003：回绕查找 —— 开启 `wrapAround`，在末尾匹配项后查找下一个时回绕到首个匹配项。
    func testWrapAround() throws {
        let text = "abc abc abc"
        // 未开启回绕：越过最后一个匹配后返回 nil
        let noWrap = try sut.nextMatch(in: text, query: "abc", options: [], after: 8)
        XCTAssertEqual(noWrap, NSRange(location: 8, length: 3))
        let exhausted = try sut.nextMatch(in: text, query: "abc", options: [], after: 9)
        XCTAssertNil(exhausted)
        // 开启回绕：回绕到首个匹配项
        let wrapped = try sut.nextMatch(in: text, query: "abc", options: [.wrapAround], after: 9)
        XCTAssertEqual(wrapped, NSRange(location: 0, length: 3))
    }

    /// UT-FIND-004：非法正则 —— 以非法正则（如 `[`）执行查找，抛出 `NPFindError.invalidRegex`。
    func testInvalidRegexThrows() {
        XCTAssertThrowsError(try sut.allMatches(in: "text", query: "[", options: [.regularExpression])) { error in
            guard case NPFindError.invalidRegex = error else {
                XCTFail("期望 NPFindError.invalidRegex，实际 \(error)")
                return
            }
        }
    }

    /// UT-FIND-006：空查询 —— 不崩溃，按契约抛出 `NPFindError.emptyQuery`。
    func testEmptyQueryThrows() {
        XCTAssertThrowsError(try sut.allMatches(in: "text", query: "", options: [])) { error in
            guard case NPFindError.emptyQuery = error else {
                XCTFail("期望 NPFindError.emptyQuery，实际 \(error)")
                return
            }
        }
        XCTAssertThrowsError(try sut.nextMatch(in: "text", query: "", options: [], after: 0))
    }

    /// 正则查找：合法正则按模式命中，默认不区分大小写。
    func testRegexMatches() throws {
        let matches = try sut.allMatches(in: "a1 B22 c333", query: "[a-z]\\d+", options: [.regularExpression])
        XCTAssertEqual(matches, [
            NSRange(location: 0, length: 2),
            NSRange(location: 3, length: 3),
            NSRange(location: 7, length: 4),
        ])
    }

    /// 正则区分大小写。
    func testRegexCaseSensitive() throws {
        let matches = try sut.allMatches(in: "a1 B22", query: "[a-z]\\d+",
                                         options: [.regularExpression, .caseSensitive])
        XCTAssertEqual(matches, [NSRange(location: 0, length: 2)])
    }

    /// 中文内容按 UTF-16 偏移返回范围。
    func testUnicodeRanges() throws {
        let matches = try sut.allMatches(in: "你好世界你好", query: "你好", options: [])
        XCTAssertEqual(matches, [NSRange(location: 0, length: 2), NSRange(location: 4, length: 2)])
    }
}
