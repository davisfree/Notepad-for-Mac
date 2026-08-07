//
//  NPFindBarViewTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPFindBarView` 属性与匹配统计测试（UI 冒烟；布局以 typecheck 验收）。
@MainActor
final class NPFindBarViewTests: XCTestCase {

    /// 被测对象（SUT，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var sut: NPFindBarView!

    override func setUp() {
        super.setUp()
        sut = NPFindBarView(frame: NSRect(x: 0, y: 0, width: 600, height: NPFindBarView.singleLineHeight))
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    /// findText / replaceText 读写。
    func testTextProperties() {
        sut.findText = "hello"
        sut.replaceText = "world"
        XCTAssertEqual(sut.findText, "hello")
        XCTAssertEqual(sut.replaceText, "world")
    }

    /// options 与"区分大小写"复选框映射。
    func testOptionsMapping() {
        sut.options = [.caseSensitive]
        XCTAssertTrue(sut.options.contains(.caseSensitive))
        sut.options = []
        XCTAssertFalse(sut.options.contains(.caseSensitive))
    }

    /// 替换模式展开/收起回调高度（44 / 76pt，02 §5.2）。
    func testReplaceModeHeightChange() {
        var heights: [CGFloat] = []
        sut.onHeightChange = { height in
            heights.append(height)
        }
        sut.isReplaceMode = true
        sut.isReplaceMode = false
        XCTAssertEqual(heights, [NPFindBarView.expandedHeight, NPFindBarView.singleLineHeight])
    }

    /// 匹配统计赋值（含"未找到"与隐藏）不崩溃。
    func testMatchResultAssignment() {
        sut.matchResult = NPMatchResult(currentIndex: 3, totalCount: 17)
        sut.matchResult = NPMatchResult(currentIndex: 0, totalCount: 0)
        sut.matchResult = nil
        XCTAssertNil(sut.matchResult)
    }
}
