//
//  NPPrintServiceTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// 打印分页与文案测试（`NPPrintFormatter` / `NPPrintPaginator` / `NPPrintTextView` 纯逻辑；
/// `NSPrintOperation` 面板流程无法 headless，以 typecheck 验收）。
@MainActor
final class NPPrintServiceTests: XCTestCase {

    /// 测试打印信息（A4，固定页边距）
    private var printInfo: NSPrintInfo!
    /// 内容区尺寸
    private var contentSize: NSSize {
        NPPrintPaginator.contentSize(for: printInfo,
                                     headerHeight: NPPrintTextView.headerHeight,
                                     footerHeight: NPPrintTextView.footerHeight)
    }

    override func setUp() {
        super.setUp()
        printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595, height: 842)
        printInfo.leftMargin = 50
        printInfo.rightMargin = 50
        printInfo.topMargin = 60
        printInfo.bottomMargin = 60
    }

    override func tearDown() {
        printInfo = nil
        super.tearDown()
    }

    /// 页脚文案：经 `Print.PageXOfY` 本地化模板格式化。
    func testFooterText() {
        let template = NSLocalizedString("Print.PageXOfY", comment: "")
        XCTAssertEqual(NPPrintFormatter.footerText(page: 1, totalPages: 3), String(format: template, 1, 3))
    }

    /// 内容区尺寸 = 纸张 - 页边距 - 页眉页脚。
    func testContentSize() {
        XCTAssertEqual(contentSize, NSSize(width: 495, height: 674))
    }

    /// 短文本与空文档均为 1 页。
    func testShortTextSinglePage() {
        let font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
        let short = NPPrintPaginator.makeLayoutManager(text: "Hello", font: font, contentSize: contentSize)
        XCTAssertEqual(short.pageCount, 1)
        let empty = NPPrintPaginator.makeLayoutManager(text: "", font: font, contentSize: contentSize)
        XCTAssertEqual(empty.pageCount, 1)
    }

    /// 长文本分页：页数 > 1，每页一个 textContainer。
    func testLongTextPagination() {
        let font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
        let longText = (1 ... 2000).map { "第 \($0) 行：The quick brown fox jumps over the lazy dog." }
            .joined(separator: "\n")
        let result = NPPrintPaginator.makeLayoutManager(text: longText, font: font, contentSize: contentSize)
        XCTAssertGreaterThan(result.pageCount, 5)
        XCTAssertEqual(result.layoutManager.textContainers.count, result.pageCount)
    }

    /// 打印视图：尺寸为纸张 × 页数，第 1 页在顶部，knowsPageRange 报告正确范围。
    func testPrintTextViewPagination() {
        let font = NSFont.userFixedPitchFont(ofSize: 12) ?? NSFont.systemFont(ofSize: 12)
        let longText = (1 ... 500).map { "line \($0)" }.joined(separator: "\n")
        let view = NPPrintTextView(text: longText, font: font, title: "test.txt", printInfo: printInfo)
        XCTAssertEqual(view.frame.width, 595)
        XCTAssertEqual(view.frame.height, 842 * CGFloat(view.pageCount))
        XCTAssertEqual(view.rectForPage(1).origin.y, 842 * CGFloat(view.pageCount - 1))
        XCTAssertEqual(view.rectForPage(view.pageCount).origin.y, 0)
        let rangePointer = UnsafeMutablePointer<NSRange>.allocate(capacity: 1)
        defer {
            rangePointer.deallocate()
        }
        XCTAssertTrue(view.knowsPageRange(rangePointer))
        XCTAssertEqual(rangePointer.pointee, NSRange(location: 1, length: view.pageCount))
    }
}
