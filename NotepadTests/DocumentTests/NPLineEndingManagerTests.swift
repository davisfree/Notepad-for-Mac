//
//  NPLineEndingManagerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPLineEndingManager` 换行符检测与转换测试（覆盖 `05_TEST_PLAN.md` UT-LE-001 ~ UT-LE-006）。
final class NPLineEndingManagerTests: XCTestCase {

    /// UT-LE-001：纯 LF 检测 —— `Line1\nLine2` 判定为 `.lf`。
    func testDetectLF() {
        XCTAssertEqual(NPLineEndingManager.detect(in: "Line1\nLine2"), .lf)
    }

    /// UT-LE-002：纯 CRLF 检测 —— `Line1\r\nLine2` 判定为 `.crlf`。
    func testDetectCRLF() {
        XCTAssertEqual(NPLineEndingManager.detect(in: "Line1\r\nLine2"), .crlf)
    }

    /// UT-LE-003：纯 CR 检测 —— `Line1\rLine2` 判定为 `.cr`。
    func testDetectCR() {
        XCTAssertEqual(NPLineEndingManager.detect(in: "Line1\rLine2"), .cr)
    }

    /// UT-LE-004：混合换行符 —— 以数量最多的为准。
    func testDetectMixedLineEndings() {
        XCTAssertEqual(NPLineEndingManager.detect(in: "Line1\nLine2\nLine3\r\n"), .lf)
        XCTAssertEqual(NPLineEndingManager.detect(in: "Line1\r\nLine2\r\nLine3\n"), .crlf)
    }

    /// UT-LE-005：LF 转 CRLF —— 所有 `\n` 变为 `\r\n`。
    func testNormalizeLFToCRLF() {
        XCTAssertEqual(NPLineEndingManager.normalize("Line1\nLine2\n", to: .crlf), "Line1\r\nLine2\r\n")
    }

    /// UT-LE-006：CRLF 转 LF —— 所有 `\r\n` 变为 `\n`。
    func testNormalizeCRLFToLF() {
        XCTAssertEqual(NPLineEndingManager.normalize("Line1\r\nLine2\r\n", to: .lf), "Line1\nLine2\n")
    }

    /// 混合换行归一：先统一为 LF 再转目标格式。
    func testNormalizeMixedLineEndings() {
        XCTAssertEqual(NPLineEndingManager.normalize("a\nb\r\nc\rd", to: .crlf), "a\r\nb\r\nc\r\nd")
        XCTAssertEqual(NPLineEndingManager.normalize("a\nb\r\nc\rd", to: .cr), "a\rb\rc\rd")
        XCTAssertEqual(NPLineEndingManager.normalize("a\nb\r\nc\rd", to: .lf), "a\nb\nc\nd")
    }

    /// 无换行符时检测返回默认 `.lf`。
    func testDetectNoLineEndingReturnsLF() {
        XCTAssertEqual(NPLineEndingManager.detect(in: "NoLineEnding"), .lf)
        XCTAssertEqual(NPLineEndingManager.detect(in: ""), .lf)
    }
}
