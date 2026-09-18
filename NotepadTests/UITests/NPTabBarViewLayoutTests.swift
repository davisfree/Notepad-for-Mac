//
//  NPTabBarViewLayoutTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import XCTest
@testable import Notepad

/// 标签栏卡片定位回归测试。
///
/// 背景（真实缺陷）：卡片位置只在 `NPTabBarView.layout()` 里计算，而 AppKit 要到下一个
/// 更新周期才调用它。于是 `addTab` 之后新卡片会保持 `frame == .zero`——也就是被画在
/// 标签栏**最左端**（且因后加入而位于最上层），用户看到的就是"新建的标签显示在标签栏
/// 最左边而不是最右边"。因此断言必须发生在 `addTab` 返回的那一刻，不能先手动触发布局。
@MainActor
final class NPTabBarViewLayoutTests: XCTestCase {

    /// 承载标签组的窗口控制器
    private var windowController: NPEditorWindowController!
    /// 本次测试创建的文档（拆除时注销会话缓存）
    private var documents: [NPTextDocument] = []

    override func tearDown() {
        windowController?.close()
        windowController = nil
        // 摘除文档：`AppDelegate.newTab(_:)` 会把文档登记进 NSDocumentController，
        // 留着会污染后续用例（如会话恢复用例的文档查找）
        for document in documents {
            NPBackupService.shared.unregisterDocument(document)
            for controller in document.windowControllers {
                document.removeWindowController(controller)
            }
            document.updateChangeCount(.changeCleared)
            document.close()
            NSDocumentController.shared.removeDocument(document)
        }
        documents = []
        super.tearDown()
    }

    /// 新建标签必须在 `addTab` 返回时就已经位于最右侧（不得等待 AppKit 的延迟布局）。
    func testNewTabIsRightmostImmediatelyAfterAdd() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        bar.layoutSubtreeIfNeeded()

        let document = NPTextDocument()
        documents.append(document)
        windowController.addTab(for: document)

        let frames = bar.subviews.map(\.frame)
        XCTAssertEqual(frames.count, 2, "标签栏子视图数应与标签数一致")
        XCTAssertGreaterThan(frames[1].minX, frames[0].minX,
                             "新建标签必须在 addTab 返回时就位于最右，而不是停在 frame=.zero（最左端）")
        XCTAssertEqual(bar.selectedIndex, 1, "新建标签应被选中（最右）")
    }

    /// 多个标签时 x 坐标必须严格递增，且不会停留在最左端。
    func testTabsAreLaidOutLeftToRightWithoutDeferredPass() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        for _ in 0 ..< 2 {
            let document = NPTextDocument()
            documents.append(document)
            windowController.addTab(for: document)
        }

        let frames = bar.subviews.map(\.frame)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].minX, NPTabBarView.barLeadingInset, accuracy: 0.5,
                       "首个标签应在左端内缩处")
        for index in 1 ..< frames.count {
            XCTAssertGreaterThan(frames[index].minX, frames[index - 1].minX,
                                 "第 \(index + 1) 个标签应在第 \(index) 个标签右侧")
        }
        XCTAssertEqual(bar.selectedIndex, 2, "最后一个标签应被选中")
    }

    /// 关闭左侧标签后，剩余标签必须立即前移补位（同样不能等待延迟布局）。
    func testRemainingTabsReflowImmediatelyAfterRemoval() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        let document = NPTextDocument()
        documents.append(document)
        windowController.addTab(for: document)
        let beforeFrames = bar.subviews.map(\.frame)

        bar.removeTab(at: 0)

        let afterFrames = bar.subviews.map(\.frame)
        XCTAssertEqual(afterFrames.count, 1, "关闭后应只剩一个标签")
        XCTAssertLessThan(afterFrames[0].minX, beforeFrames[1].minX,
                          "剩余标签应回到最左侧并变宽，而不是保留原位置")
        XCTAssertEqual(afterFrames[0].minX, NPTabBarView.barLeadingInset, accuracy: 0.5)
    }

    /// 复现用户路径：文件 → 新建标签页（`AppDelegate.newTab(_:)`）后，新标签必须在最右侧。
    func testMenuNewTabAppendsToRightmost() throws {
        let window = try makeWindowWithFirstTab()
        let bar = windowController.tabBarController.tabBar

        // 让路由把本窗口认作"最近活跃窗口"（测试宿主无 key/main 窗口）
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        appDelegate.newTab(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        window.contentView?.layoutSubtreeIfNeeded()

        let entries = windowController.tabBarController.entries
        documents.append(contentsOf: entries.map(\.document))

        XCTAssertEqual(entries.count, 2, "菜单新建标签页应只增加一个标签")
        XCTAssertEqual(bar.subviews.count, 2, "标签栏子视图数应与标签数一致")
        XCTAssertGreaterThan(bar.subviews[1].frame.minX, bar.subviews[0].frame.minX,
                             "菜单新建的标签应位于最右")
        XCTAssertEqual(bar.selectedIndex, 1, "新建标签应被选中")
    }

    // MARK: - 辅助

    /// 经生产路径装配前台窗口（首标签为返回窗口内的唯一标签）。
    /// - Returns: 目标窗口
    private func makeWindowWithFirstTab() throws -> NSWindow {
        let first = NPTextDocument()
        documents.append(first)
        windowController = NPTabWindowManager.shared.openInNewWindow(first)
        let window = try XCTUnwrap(windowController.window)
        window.setContentSize(NSSize(width: 800, height: 600))
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
