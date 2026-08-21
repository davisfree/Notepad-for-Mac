//
//  NPMarkdownRendererTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-21.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import XCTest
@testable import Notepad

/// `NPMarkdownRenderer` 测试（帮助窗口正文渲染）。
@MainActor
final class NPMarkdownRendererTests: XCTestCase {

    /// 取指定子串首次出现处的字体属性。
    private func font(of substring: String, in rendered: NSAttributedString,
                      file: StaticString = #filePath, line: UInt = #line) throws -> NSFont {
        let range = (rendered.string as NSString).range(of: substring)
        XCTAssertNotEqual(range.location, NSNotFound, "未找到子串：\(substring)", file: file, line: line)
        return try XCTUnwrap(rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
                             file: file, line: line)
    }

    /// 标记符号被剥离，不出现在渲染结果中。
    func testStripsMarkdownMarkers() {
        let rendered = NPMarkdownRenderer.render(markdown: "# 标题\n\n- **加粗** 与 `代码`\n")
        XCTAssertFalse(rendered.string.contains("#"))
        XCTAssertFalse(rendered.string.contains("**"))
        XCTAssertFalse(rendered.string.contains("`"))
    }

    /// 一级标题：加粗、20pt。
    func testHeadingLevel1() throws {
        let rendered = NPMarkdownRenderer.render(markdown: "# Notepad 帮助\n")
        let font = try font(of: "Notepad 帮助", in: rendered)
        XCTAssertEqual(font.pointSize, 20)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    /// 二级标题：加粗、16pt；三级标题：加粗、14pt。
    func testHeadingLevels2And3() throws {
        let rendered = NPMarkdownRenderer.render(markdown: "## 二级\n\n### 三级\n")
        let level2 = try font(of: "二级", in: rendered)
        let level3 = try font(of: "三级", in: rendered)
        XCTAssertEqual(level2.pointSize, 16)
        XCTAssertEqual(level3.pointSize, 14)
        XCTAssertTrue(NSFontManager.shared.traits(of: level2).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: level3).contains(.boldFontMask))
    }

    /// 行内 **加粗** 应用粗体，其余文字保持正文字体。
    func testInlineBold() throws {
        let rendered = NPMarkdownRenderer.render(markdown: "普通 **重点** 收尾\n")
        let bold = try font(of: "重点", in: rendered)
        let plain = try font(of: "普通", in: rendered)
        XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: plain).contains(.boldFontMask))
        XCTAssertEqual(plain.pointSize, NPMarkdownRenderer.bodyFontSize)
    }

    /// 行内 `代码` 应用等宽字体。
    func testInlineCode() throws {
        let rendered = NPMarkdownRenderer.render(markdown: "按 `⌘S` 保存\n")
        let code = try font(of: "⌘S", in: rendered)
        XCTAssertTrue(code.isFixedPitch)
    }

    /// 列表项渲染为圆点前缀，标记 "- " 被剥离。
    func testListItem() {
        let rendered = NPMarkdownRenderer.render(markdown: "- 第一项\n- 第二项\n")
        XCTAssertTrue(rendered.string.contains("•  第一项"))
        XCTAssertTrue(rendered.string.contains("•  第二项"))
        XCTAssertFalse(rendered.string.contains("- 第"))
    }

    /// 空行被跳过（段落间距由样式承担），且正文文字带 label 颜色。
    func testSkipsBlankLinesAndAppliesLabelColor() throws {
        let rendered = NPMarkdownRenderer.render(markdown: "甲\n\n\n乙\n")
        XCTAssertFalse(rendered.string.contains("\n\n"))
        let colorLocation = try XCTUnwrap(rendered.string.range(of: "甲"))
        let color = rendered.attribute(.foregroundColor,
                                       at: rendered.string.distance(from: rendered.string.startIndex,
                                                                    to: colorLocation.lowerBound),
                                       effectiveRange: nil) as? NSColor
        XCTAssertNotNil(color)
    }
}
