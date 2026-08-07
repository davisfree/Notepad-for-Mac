//
//  NPCrashSanitizerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-06.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPCrashSanitizer` 测试（05_TEST_PLAN.md UT-CRASH-001 ~ 004）。
final class NPCrashSanitizerTests: XCTestCase {

    /// 主目录路径（含其下子路径）被脱敏。
    func testRedactsHomeDirectoryPath() {
        let home = NSHomeDirectory()
        let text = "Failed to read \(home)/Documents/secret.txt"
        let sanitized = NPCrashSanitizer.sanitize(text)
        XCTAssertFalse(sanitized.contains(home))
        XCTAssertTrue(sanitized.contains("<redacted>"))
    }

    /// `file://` URL 被整体脱敏（路径与主机部分一并替换）。
    func testRedactsFileURL() {
        let text = "Failed to open file://\(NSHomeDirectory())/a/b.txt at line 12"
        let sanitized = NPCrashSanitizer.sanitize(text)
        XCTAssertFalse(sanitized.contains("file://"))
        XCTAssertFalse(sanitized.contains(NSHomeDirectory()))
        XCTAssertTrue(sanitized.contains("<redacted>"))
    }

    /// 普通文本（不含本机路径）保持不变。
    func testKeepsPlainText() {
        let text = "Out of memory: unable to allocate buffer"
        XCTAssertEqual(NPCrashSanitizer.sanitize(text), text)
    }

    /// 空字符串安全通过。
    func testHandlesEmptyString() {
        XCTAssertEqual(NPCrashSanitizer.sanitize(""), "")
    }
}
