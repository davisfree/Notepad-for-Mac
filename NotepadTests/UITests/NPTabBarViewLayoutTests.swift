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
/// 两个关注点：
/// 1. **插入位置（用户偏好）**：文件 → 新建标签页（⌘N）的新标签落在标签栏**最左端**；
///    打开文件、会话恢复、拖拽重排等路径仍追加到最右端并保序。
/// 2. **布局时机**：卡片位置只在 `NPTabBarView.layout()` 里算，而 AppKit 要到下一个更新周期
///    才调用它；若增删标签时不主动重排，新卡片会带着 `frame == .zero` 停在标签栏最左端。
///    因此断言必须发生在增删返回的那一刻，不能先手动触发布局。
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

    /// 前置插入（新建标签页）必须立刻占据最左端，且既有标签整体后移。
    func testLeadingInsertLandsLeftmostImmediately() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        bar.layoutSubtreeIfNeeded()
        let firstTabFrame = try XCTUnwrap(cardViews(bar).first?.frame)

        let document = NPTextDocument()
        documents.append(document)
        windowController.addTab(for: document, position: .leading)

        let frames = cardViews(bar).map(\.frame)
        XCTAssertEqual(frames.count, 2, "标签栏子视图数应与标签数一致")
        XCTAssertEqual(frames[0].midX, firstTabFrame.midX, accuracy: 0.5,
                       "新标签必须占据第一张卡片的位置（最左端）")
        XCTAssertGreaterThan(frames[1].minX, frames[0].minX,
                             "既有标签必须整体后移")
        XCTAssertEqual(bar.selectedIndex, 0, "新建标签应被选中（最左端）")
        XCTAssertTrue(windowController.tabBarController.entries[0].document === document)
    }

    /// 追加路径（打开文件 / 会话恢复 / 复制标签）仍为最右端，且保序。
    func testTrailingAddsStayRightmostAndKeepOrder() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        var added: [NPTextDocument] = []
        for _ in 0 ..< 2 {
            let document = NPTextDocument()
            added.append(document)
            documents.append(document)
            windowController.addTab(for: document, position: .trailing)
        }

        let frames = cardViews(bar).map(\.frame)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].minX, NPTabBarView.barLeadingInset, accuracy: 0.5,
                       "首个标签仍在左端内缩处（追加不改变既有顺序）")
        for index in 1 ..< frames.count {
            XCTAssertGreaterThan(frames[index].minX, frames[index - 1].minX,
                                 "第 \(index + 1) 个标签应在第 \(index) 个标签右侧")
        }
        XCTAssertEqual(bar.selectedIndex, 2, "最后一个标签应被选中")
        XCTAssertTrue(windowController.tabBarController.entries[1].document === added[0])
        XCTAssertTrue(windowController.tabBarController.entries[2].document === added[1])
    }

    /// 关闭左侧标签后，剩余标签必须立即前移补位（同样不能等待延迟布局）。
    func testRemainingTabsReflowImmediatelyAfterRemoval() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        let document = NPTextDocument()
        documents.append(document)
        windowController.addTab(for: document, position: .trailing)
        let beforeFrames = cardViews(bar).map(\.frame)

        bar.removeTab(at: 0)

        let afterFrames = cardViews(bar).map(\.frame)
        XCTAssertEqual(afterFrames.count, 1, "关闭后应只剩一个标签")
        XCTAssertLessThan(afterFrames[0].minX, beforeFrames[1].minX,
                          "剩余标签应回到最左侧并变宽，而不是保留原位置")
        XCTAssertEqual(afterFrames[0].minX, NPTabBarView.barLeadingInset, accuracy: 0.5)
    }

    /// 复现用户路径：文件 → 新建标签页（`AppDelegate.newTab(_:)`）后，新标签必须在**最左端**。
    func testMenuNewTabInsertsAtLeftmost() throws {
        let window = try makeWindowWithFirstTab()
        let bar = windowController.tabBarController.tabBar
        let existingDocument = try XCTUnwrap(windowController.tabBarController.entries.first?.document)
        let expectedWindowCount = NPTabWindowManager.shared.windowControllers.count
        let existingIDs = windowController.tabBarController.entries.map { ObjectIdentifier($0.document) }

        // 让路由把本窗口认作"最近活跃窗口"（测试宿主没有 key/main 窗口）
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        appDelegate.newTab(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let entries = windowController.tabBarController.entries
        documents.append(contentsOf: entries.map(\.document))

        XCTAssertEqual(entries.count, 2, "菜单新建标签页应只增加一个标签")
        XCTAssertEqual(cardViews(bar).count, 2, "标签栏子视图数应与标签数一致")
        XCTAssertEqual(cardViews(bar)[0].frame.minX, NPTabBarView.barLeadingInset, accuracy: 0.5,
                       "新建标签应位于最左端")
        XCTAssertGreaterThan(cardViews(bar)[1].frame.minX, cardViews(bar)[0].frame.minX,
                             "原标签应移到新建标签右侧")
        XCTAssertEqual(bar.selectedIndex, 0, "新建标签应被选中（最左端）")
        XCTAssertTrue(entries[1].document === existingDocument, "原标签应后移一位而不是被替换")
        // 不得出现同一文档的重复标签（另一条路径也插过一次），也不得新开窗口
        let newDocuments = entries.map(\.document).filter { !existingIDs.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(newDocuments.count, 1, "⌘N 只应新增一个文档标签，不得重复")
        XCTAssertTrue(entries[0].document === newDocuments[0], "新增文档应落在最左端")
        XCTAssertEqual(NPTabWindowManager.shared.windowControllers.count, expectedWindowCount,
                       "⌘N 应在当前窗口内加标签，不得新开窗口")
    }

    /// 工厂路径（AppKit `makeWindowControllers` → `acquireWindowController`）：
    /// **未命名新文档必须落在最左端**（`insertTab(0)`），不能追加到最右。
    func testFactoryPathPutsUntitledDocumentLeftmost() throws {
        let window = try makeWindowWithFirstTab()
        let bar = windowController.tabBarController.tabBar

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let document = NPTextDocument()
        documents.append(document)
        XCTAssertNil(document.fileURL, "本用例针对无标题新文档")

        let created = NPTabWindowManager.shared.acquireWindowController(for: document)
        XCTAssertNil(created, "应作为标签加入现有窗口，而不是自建窗口控制器")

        let entries = windowController.tabBarController.entries
        XCTAssertEqual(entries.count, 2, "只应增加一个标签")
        XCTAssertTrue(entries[0].document === document, "未命名新文档必须落在索引 0（最左端）")
        XCTAssertEqual(cardViews(bar)[0].frame.minX, NPTabBarView.barLeadingInset, accuracy: 0.5)
    }

    /// 工厂路径（打开文件经 AppKit `makeWindowControllers`）：**新增标签一律落在最左端**（`insertTab(0)`）。
    func testFactoryPathPutsOpenedFileLeftmost() throws {
        let window = try makeWindowWithFirstTab()
        let bar = windowController.tabBarController.tabBar

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-tab-factory-\(UUID().uuidString).txt")
        try "opened".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let document = try NPTextDocument(contentsOf: fileURL, ofType: "public.plain-text")
        documents.append(document)

        _ = NPTabWindowManager.shared.acquireWindowController(for: document)

        let entries = windowController.tabBarController.entries
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.first?.document === document, "打开的文件也应落在最左端（insertTab(0)）")
        XCTAssertEqual(cardViews(bar)[0].frame.minX, NPTabBarView.barLeadingInset, accuracy: 0.5)
        XCTAssertGreaterThan(cardViews(bar)[1].frame.minX, cardViews(bar)[0].frame.minX,
                             "既有的标签应整体后移")
    }

    /// 右端"+"按钮：存在、贴右端、且不计入标签。
    func testNewTabButtonIsRightAlignedAndNotATab() throws {
        _ = try makeWindowWithFirstTab()

        let bar = windowController.tabBarController.tabBar
        bar.layoutSubtreeIfNeeded()

        let button = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first, "标签栏应有右端 + 按钮")
        XCTAssertTrue(button.isEnabled, "按钮应可用")
        XCTAssertEqual(bar.tabs.count, 1, "按钮不得计入标签数")

        let cards = cardViews(bar)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(button.frame.maxX, bar.bounds.maxX - 4.0, accuracy: 0.5, "按钮应贴右端内缩 4pt")
        XCTAssertGreaterThan(button.frame.minX, cards[0].frame.maxX, "按钮应在卡片区域右侧，不重叠")
    }

    /// 右端"+"按钮点击 = 新建标签页：新标签落在最左端并被选中，且不新开窗口。
    func testNewTabButtonInsertsLeftmost() throws {
        let window = try makeWindowWithFirstTab()
        let bar = windowController.tabBarController.tabBar
        let existingDocument = try XCTUnwrap(windowController.tabBarController.entries.first?.document)
        let expectedWindowCount = NPTabWindowManager.shared.windowControllers.count
        let existingIDs = windowController.tabBarController.entries.map { ObjectIdentifier($0.document) }

        // 让路由把本窗口认作"最近活跃窗口"（测试宿主没有 key/main 窗口）
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        let button = try XCTUnwrap(bar.subviews.compactMap { $0 as? NSButton }.first)
        button.performClick(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        let entries = windowController.tabBarController.entries
        documents.append(contentsOf: entries.map(\.document))
        let newDocuments = entries.map(\.document).filter { !existingIDs.contains(ObjectIdentifier($0)) }

        XCTAssertEqual(entries.count, 2, "只应新增一个标签")
        XCTAssertEqual(newDocuments.count, 1, "按钮应只新建一个文档标签，不得重复")
        XCTAssertTrue(entries[0].document === newDocuments[0], "按钮新建的标签应落在最左端")
        XCTAssertTrue(entries[1].document === existingDocument, "原标签应后移一位")
        XCTAssertEqual(bar.selectedIndex, 0, "新标签应被选中（最左端）")
        XCTAssertEqual(NPTabWindowManager.shared.windowControllers.count, expectedWindowCount,
                       "应在当前窗口内加标签，不得新开窗口")
    }

    // MARK: - 辅助

    /// 标签卡片视图（按标签序；排除右端"+"按钮）
    private func cardViews(_ bar: NPTabBarView) -> [NPTabItemView] {
        bar.subviews.compactMap { $0 as? NPTabItemView }
    }

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
