//
//  NPTabGroupModelTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPTabGroupModel` 标签组模型测试（增删/排序/选择边界/拖出判定）。
final class NPTabGroupModelTests: XCTestCase {

    /// 被测对象（struct，每用例独立构造）
    private var sut = NPTabGroupModel()
    /// 测试标识
    private let ids = (0 ..< 4).map { _ in UUID() }

    override func setUp() {
        super.setUp()
        sut = NPTabGroupModel()
    }

    /// 追加即选中（Win11 新标签立即成为当前标签）。
    func testAppendSelectsNewTab() {
        sut.append(ids[0])
        XCTAssertEqual(sut.selectedIndex, 0)
        sut.append(ids[1])
        XCTAssertEqual(sut.selectedIndex, 1)
        XCTAssertEqual(sut.count, 2)
    }

    /// 移除当前项之前的标签：选中索引前移。
    func testRemoveBeforeSelection() {
        for id in ids.prefix(3) {
            sut.append(id)
        }
        sut.select(2)
        sut.remove(at: 0)
        XCTAssertEqual(sut.selectedIndex, 1)
        XCTAssertEqual(sut.count, 2)
    }

    /// 移除当前项：选中同位置后继（末尾则前驱）。
    func testRemoveSelectedTab() {
        for id in ids.prefix(3) {
            sut.append(id)
        }
        sut.select(1)
        sut.remove(at: 1)
        XCTAssertEqual(sut.selectedIndex, 1) // 原索引 2 的后继补位
        sut.remove(at: 1)
        XCTAssertEqual(sut.selectedIndex, 0) // 末尾移除后选中前驱
    }

    /// 全部移除：选中索引归 -1。
    func testRemoveAll() {
        sut.append(ids[0])
        sut.remove(at: 0)
        XCTAssertEqual(sut.selectedIndex, -1)
        XCTAssertEqual(sut.count, 0)
    }

    /// 越界移除忽略。
    func testRemoveOutOfBoundsIgnored() {
        sut.append(ids[0])
        sut.remove(at: 5)
        XCTAssertEqual(sut.count, 1)
    }

    /// 拖拽排序：元素移动且选中跟随同一标签。
    func testMoveTab() {
        for id in ids.prefix(3) {
            sut.append(id)
        }
        sut.select(0)
        sut.move(from: 0, to: 2)
        XCTAssertEqual(sut.identifiers, [ids[1], ids[2], ids[0]])
        XCTAssertEqual(sut.selectedIndex, 2)
    }

    /// 移动修正中间选中索引。
    func testMoveAdjustsMiddleSelection() {
        for id in ids.prefix(4) {
            sut.append(id)
        }
        sut.select(2)
        sut.move(from: 0, to: 3)
        XCTAssertEqual(sut.selectedIndex, 1)
    }

    /// 同位/越界移动忽略。
    func testMoveEdgeCasesIgnored() {
        for id in ids.prefix(2) {
            sut.append(id)
        }
        sut.move(from: 0, to: 0)
        sut.move(from: 0, to: 9)
        XCTAssertEqual(sut.identifiers, [ids[0], ids[1]])
    }

    /// 选择越界忽略。
    func testSelectOutOfBoundsIgnored() {
        sut.append(ids[0])
        sut.select(7)
        XCTAssertEqual(sut.selectedIndex, 0)
    }

    /// 拖出判定：超出标签栏区域 20pt（任意方向）。
    func testDragOutThreshold() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 32)
        XCTAssertFalse(NPTabGroupModel.isDragOut(point: NSPoint(x: 400, y: 16), in: bounds))
        XCTAssertFalse(NPTabGroupModel.isDragOut(point: NSPoint(x: 400, y: -20), in: bounds))
        XCTAssertTrue(NPTabGroupModel.isDragOut(point: NSPoint(x: 400, y: -21), in: bounds))
        XCTAssertTrue(NPTabGroupModel.isDragOut(point: NSPoint(x: 400, y: 53), in: bounds))
        XCTAssertTrue(NPTabGroupModel.isDragOut(point: NSPoint(x: -21, y: 16), in: bounds))
    }
}
