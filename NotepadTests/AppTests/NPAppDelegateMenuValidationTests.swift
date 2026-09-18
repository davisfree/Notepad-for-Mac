//
//  NPAppDelegateMenuValidationTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import XCTest
@testable import Notepad

/// 文件菜单可用性回归测试（打开已有文件 → 编辑 → "保存"必须可用）。
///
/// 背景：`AppDelegate.validateMenuItem(_:)` 对 `saveDocument:` 的判定依赖两个环节——
/// `currentDocument()`（`NSApp.mainWindow` → 标签组选中项）与 `isDocumentEdited`。
/// 本测试把这条链**分段断言**：任一环断掉时，失败信息会直接指出断点（A 脏状态 / B 文档解析）。
@MainActor
final class NPAppDelegateMenuValidationTests: XCTestCase {

    /// 临时文件（已有文件场景）
    private var fileURL: URL!
    /// 被测文档
    private var document: NPTextDocument!
    /// 承载文档的标签组窗口控制器
    private var windowController: NPEditorWindowController!

    override func setUp() {
        super.setUp()
        fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-menu-\(UUID().uuidString).txt")
        try? "line1\nline2\n".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        if let document {
            // 清掉会话缓存，避免污染真实备份目录（注册发生于 addTab）
            NPBackupService.shared.unregisterDocument(document)
        }
        windowController?.close()
        windowController = nil
        document = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        super.tearDown()
    }

    // MARK: - 核心回归

    /// 打开已有文件并编辑后，"保存"菜单项必须可用。
    func testSaveItemEnabledAfterEditingOpenedFile() throws {
        try openFileAndShowWindow()

        let entry = try XCTUnwrap(windowController.tabBarController.selectedEntry, "窗口应有选中标签")
        XCTAssertTrue(entry.document === document)

        // 真实编辑通路：NPEditorView.textDidChange → NPEditorController.editorDidChangeContent
        //                → syncDocument() → document.updateChangeCount(.changeDone)
        entry.editorController.editorView.textDidChange(
            Notification(name: NSText.didChangeNotification, object: nil)
        )
        XCTAssertTrue(document.isDocumentEdited, "断点 A：编辑后文档应为脏状态")

        // 断点 B：当前文档解析不得单点依赖 `NSApp.mainWindow`。
        // 测试宿主 App 处于非激活状态（`NSApp.isActive == false`），key/main 窗口均为 nil，
        // 必须回退到最近登记的可见标签组窗口，否则保存项会恒不可用。
        XCTAssertTrue(
            NPTabWindowManager.shared.activeWindowController()?
                .tabBarController.selectedEntry?.document === document,
            "当前文档解析应回退到登记窗口（key= nil main= nil 时）"
        )

        let saveItem = try XCTUnwrap(Self.saveMenuItem, "主菜单中应存在 action 为 saveDocument: 的项")
        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertTrue(appDelegate.validateMenuItem(saveItem), "打开已有文件并编辑后，保存项应可用")
    }

    /// 打开已有文件但未修改时，"保存"也应可用（对齐 Win11 记事本）。
    func testSaveItemEnabledForUnmodifiedOpenedFile() throws {
        try openFileAndShowWindow()

        XCTAssertFalse(document.isDocumentEdited, "刚打开的文件不应为脏")
        let saveItem = try XCTUnwrap(Self.saveMenuItem)
        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertTrue(appDelegate.validateMenuItem(saveItem), "存在可编辑文档时，保存项应恒可用")
    }

    /// 未命名新文档（未修改）时，"保存"也应可用（⌘S 走保存面板）。
    func testSaveItemEnabledForUntitledDocument() throws {
        document = NPTextDocument()
        try showWindow(for: document)

        let saveItem = try XCTUnwrap(Self.saveMenuItem)
        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertTrue(appDelegate.validateMenuItem(saveItem), "未命名文档的保存项应可用（触发保存面板）")
    }

    /// 只读（>10MB）文档的"保存"必须不可用（避免必然失败的写盘尝试）。
    func testSaveItemDisabledForReadOnlyDocument() throws {
        document = NPTextDocument()
        try document.read(from: Data(repeating: UInt8(ascii: "a"),
                                     count: NPConstants.largeFileThreshold + 1),
                          ofType: "public.plain-text")
        XCTAssertTrue(document.isReadOnly)
        try showWindow(for: document)

        let saveItem = try XCTUnwrap(Self.saveMenuItem)
        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertFalse(appDelegate.validateMenuItem(saveItem), "只读文档的保存项应禁用")
    }

    /// `NSApp.keyWindow` / `mainWindow` 均不可用（App 非激活）时，当前窗口解析必须回退到
    /// 最近登记的可见标签组窗口。
    ///
    /// 这正是"保存项变灰"的根因场景：`currentDocument()` 曾单点依赖 `NSApp.mainWindow`，
    /// 该值为 `nil` 时保存/另存为/打印会集体变灰且对应动作静默失效。
    func testActiveWindowFallsBackWhenNoKeyOrMainWindow() throws {
        try openFileAndShowWindow()

        let resolved = try XCTUnwrap(NPTabWindowManager.shared.activeWindowController())
        XCTAssertTrue(
            resolved.window === windowController.window,
            "应回退到最近登记的可见标签组窗口（key= nil main= nil）"
        )
        XCTAssertTrue(resolved.tabBarController.selectedEntry?.document === document)
    }

    /// 保存可用性纯函数：无文档禁用、只读禁用、可写文档（无论脏否）均启用。
    func testIsSaveEnabledRule() throws {
        XCTAssertFalse(AppDelegate.isSaveEnabled(for: nil), "无文档时保存应禁用")

        let readOnly = NPTextDocument()
        try readOnly.read(from: Data(repeating: UInt8(ascii: "a"),
                                     count: NPConstants.largeFileThreshold + 1),
                          ofType: "public.plain-text")
        XCTAssertTrue(readOnly.isReadOnly)
        XCTAssertFalse(AppDelegate.isSaveEnabled(for: readOnly), "只读文档保存/另存为应禁用")

        let writable = NPTextDocument()
        XCTAssertTrue(AppDelegate.isSaveEnabled(for: writable), "未修改的可写文档保存应可用")
        writable.updateChangeCount(.changeDone)
        XCTAssertTrue(AppDelegate.isSaveEnabled(for: writable), "已修改的可写文档保存应可用")
    }

    /// 未修改时按 ⌘S 走 `NSDocument.save(_:)`：不得弹面板、不得改动文件内容（方案 A 的前提）。
    func testSavingCleanDocumentIsSafe() throws {
        document = try NPTextDocument(contentsOf: fileURL, ofType: "public.plain-text")
        try showWindow(for: document)

        document.save(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "line1\nline2\n")
        XCTAssertFalse(document.isDocumentEdited)
    }

    /// 菜单校验发生在菜单跟踪期间（`NSApp.keyWindow` / `mainWindow` 均为 nil）时，
    /// 必须用"最近活跃窗口"解析当前文档，**不能**退化成"最近登记的窗口"。
    ///
    /// 退化会命中最后新建的窗口：于是"新建文档"保存可用，而其它已打开文件的窗口
    /// 恒解析失败 → 保存项永远变灰（真实缺陷）。
    func testActiveWindowPrefersMostRecentlyActiveOverRegistrationOrder() throws {
        // 窗口 A：先登记的"已打开文件"窗口
        try openFileAndShowWindow()
        let windowA = try XCTUnwrap(windowController.window)

        // 窗口 B：后登记的"最后新建"窗口（模拟 ⌘N 新建的窗口）
        let secondURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-menu-2-\(UUID().uuidString).txt")
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: secondURL) }
        let secondDocument = try NPTextDocument(contentsOf: secondURL, ofType: "public.plain-text")
        let secondWindowController = NPTabWindowManager.shared.openInNewWindow(secondDocument)
        defer {
            NPBackupService.shared.unregisterDocument(secondDocument)
            secondWindowController.close()
        }
        XCTAssertFalse(secondWindowController.window === windowA)

        // 用户实际在窗口 A 工作：投递 AppKit 的真实通知（等价于窗口 A 成为 key）
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: windowA)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertTrue(
            NPTabWindowManager.shared.activeWindowController()?.window === windowA,
            "应优先最近活跃窗口，而不是最近登记的窗口（B）"
        )
    }

    // MARK: - 辅助

    /// 打开临时文件并装配前台标签组窗口。
    private func openFileAndShowWindow() throws {
        document = try NPTextDocument(contentsOf: fileURL, ofType: "public.plain-text")
        try showWindow(for: document)
    }

    /// 经生产路径（`NPTabWindowManager.openInNewWindow`）装配并注册标签组窗口，并尝试置前。
    ///
    /// 不可直接使用 `NPWindowFactory.makeWindowController`：该工厂只装配，不加入文档、不注册路由。
    private func showWindow(for document: NPTextDocument) throws {
        windowController = NPTabWindowManager.shared.openInNewWindow(document)
        NSApp.activate(ignoringOtherApps: true)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    /// 主菜单中 action 为 `saveDocument:` 的菜单项（递归查找子菜单）。
    private static var saveMenuItem: NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else {
            return nil
        }
        return findItem(in: mainMenu) { item in
            item.action == #selector(AppDelegate.saveDocument(_:))
        }
    }

    /// 递归查找首个满足条件的菜单项。
    /// - Parameters:
    ///   - menu: 待搜索菜单
    ///   - predicate: 匹配条件
    /// - Returns: 菜单项
    private static func findItem(in menu: NSMenu,
                                 matching predicate: (NSMenuItem) -> Bool) -> NSMenuItem? {
        for item in menu.items {
            if predicate(item) {
                return item
            }
            if let submenu = item.submenu, let found = findItem(in: submenu, matching: predicate) {
                return found
            }
        }
        return nil
    }
}
