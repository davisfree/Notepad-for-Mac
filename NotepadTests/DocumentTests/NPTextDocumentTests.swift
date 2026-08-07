//
//  NPTextDocumentTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPTextDocument` 读写与编码处理测试（覆盖 `05_TEST_PLAN.md` UT-DOC-001 ~ UT-DOC-003）。
final class NPTextDocumentTests: XCTestCase {

    /// UT-DOC-001：新建文档 —— 编码 UTF-8，换行符 LF，无内容。
    func testNewDocumentDefaults() {
        let document = NPTextDocument()
        XCTAssertEqual(document.textContent, "")
        XCTAssertEqual(document.currentEncoding, .utf8)
        XCTAssertEqual(document.originalEncoding, .utf8)
        XCTAssertEqual(document.currentLineEnding, .lf)
        XCTAssertFalse(document.hasBOM)
        XCTAssertFalse(document.hasUnsavedChanges)
    }

    /// UT-DOC-002：读取 UTF-8 文件 —— 内容正确，编码标记 UTF-8；内存中换行符归一为 LF。
    func testUTF8RoundTrip() throws {
        let document = NPTextDocument()
        let original = "Hello, Notepad!\n第二行\n"
        let data = try XCTUnwrap(original.data(using: .utf8))

        try document.read(from: data, ofType: "public.plain-text")
        XCTAssertEqual(document.textContent, original)
        XCTAssertEqual(document.currentEncoding, .utf8)
        XCTAssertEqual(document.originalEncoding, .utf8)
        XCTAssertEqual(document.currentLineEnding, .lf)

        let written = try document.data(ofType: "public.plain-text")
        XCTAssertEqual(written, data)
    }

    /// 读取 CRLF + BOM 的 UTF-8 文件：剥离 BOM、保留 CRLF 标记、内存归一 LF，保存时还原。
    func testReadUTF8BOMWithCRLF() throws {
        let document = NPTextDocument()
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(try XCTUnwrap("Line1\r\nLine2\r\n".data(using: .utf8)))

        try document.read(from: data, ofType: "public.plain-text")
        XCTAssertTrue(document.hasBOM)
        XCTAssertEqual(document.currentLineEnding, .crlf)
        XCTAssertEqual(document.textContent, "Line1\nLine2\n")

        let written = try document.data(ofType: "public.plain-text")
        XCTAssertEqual(written, data)
    }

    /// UT-DOC-003：保存保持编码 —— 打开 GB18030（GBK 超集）文件后仍以 GB18030 保存。
    func testSavePreservesEncoding() throws {
        let document = NPTextDocument()
        let text = "你好世界，这是一个中文测试文件。"
        let data = try XCTUnwrap(text.data(using: .gb18030))

        try document.read(from: data, ofType: "public.plain-text")
        XCTAssertEqual(document.currentEncoding, .gb18030)
        XCTAssertEqual(document.originalEncoding, .gb18030)
        XCTAssertEqual(document.textContent, text)

        let written = try document.data(ofType: "public.plain-text")
        XCTAssertEqual(written, data)
    }

    /// 切换编码 / 换行符后保存结果随之变化，并标记文档已修改。
    func testChangeEncodingAndLineEnding() throws {
        let document = NPTextDocument()
        try document.read(from: Data("Line1\nLine2".utf8), ofType: "public.plain-text")

        try document.changeEncoding(to: .utf16LittleEndian)
        XCTAssertEqual(document.currentEncoding, .utf16LittleEndian)
        XCTAssertTrue(document.hasUnsavedChanges)

        document.changeLineEnding(to: .crlf)
        XCTAssertEqual(document.currentLineEnding, .crlf)
        XCTAssertEqual(document.textContent, "Line1\r\nLine2")

        let written = try document.data(ofType: "public.plain-text")
        let expected = try XCTUnwrap("Line1\r\nLine2".data(using: .utf16LittleEndian))
        XCTAssertEqual(written, expected)
    }
}
