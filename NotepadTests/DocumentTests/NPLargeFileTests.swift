//
//  NPLargeFileTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// 大文件只读策略测试（PRD FR-001、IT-DOC-ED-006；阈值 `NPConstants.largeFileThreshold`）。
final class NPLargeFileTests: XCTestCase {

    /// 阈值为 10MB。
    func testThresholdConstant() {
        XCTAssertEqual(NPConstants.largeFileThreshold, 10 * 1024 * 1024)
    }

    /// 小文件：非只读，可保存。
    func testSmallFileNotReadOnly() throws {
        let document = NPTextDocument()
        let data = Data("小文件内容\n".utf8)
        try document.read(from: data, ofType: "public.plain-text")
        XCTAssertFalse(document.isReadOnly)
        XCTAssertEqual(try document.data(ofType: "public.plain-text"), data)
    }

    /// 边界：恰好 10MB 非只读，10MB+1 字节只读。
    func testThresholdBoundary() throws {
        let exactDocument = NPTextDocument()
        try exactDocument.read(from: Data(repeating: UInt8(ascii: "a"), count: NPConstants.largeFileThreshold),
                               ofType: "public.plain-text")
        XCTAssertFalse(exactDocument.isReadOnly)

        let largeDocument = NPTextDocument()
        try largeDocument.read(from: Data(repeating: UInt8(ascii: "b"), count: NPConstants.largeFileThreshold + 1),
                               ofType: "public.plain-text")
        XCTAssertTrue(largeDocument.isReadOnly)
    }

    /// IT-DOC-ED-006：15MB 文件整体加载且只读，保存抛 `NPError.documentIsReadOnly`。
    func testLargeFileReadOnlyAndSaveBlocked() throws {
        let line = "0123456789 abcdefghij 这是一行中文测试文本用于大文件。\n"
        let text = String(repeating: line, count: 15 * 1024 * 1024 / (line as NSString).length + 1)
        let document = NPTextDocument()
        try document.read(from: Data(text.utf8), ofType: "public.plain-text")
        XCTAssertTrue(document.isReadOnly)
        XCTAssertEqual(document.textContent.count, text.count)
        XCTAssertThrowsError(try document.data(ofType: "public.plain-text")) { error in
            guard case NPError.documentIsReadOnly = error else {
                XCTFail("期望 NPError.documentIsReadOnly，实际 \(error)")
                return
            }
        }
    }
}
