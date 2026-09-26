//
//  NPSessionRestoreTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import XCTest
@testable import Notepad

/// 会话恢复的"文件关联"回归测试。
///
/// 缺陷：打开已有文件 → 退出 → 重启，内容正确但标题变成"未命名"。
/// 原因：沙盒的"用户选择文件"权限只对当前进程有效，仅凭元数据里的路径重启后
/// 打不开原文件，恢复逻辑落到"原文件已丢失"兜底分支（缓存内容 + 未命名文档）。
/// 修复：元数据记录原文件的 security-scoped bookmark，恢复时据此重新获得访问权。
@MainActor
final class NPSessionRestoreTests: XCTestCase {

    /// 测试专用临时目录
    private var directory: URL!
    /// 本测试创建/恢复出的文档（tearDown 清理，避免污染其它用例）
    private var cleanupDocuments: [NPTextDocument] = []

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-restore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        for document in cleanupDocuments {
            NPBackupService.shared.unregisterDocument(document)
            for controller in document.windowControllers {
                if let editorController = controller as? NPEditorWindowController {
                    NPTabWindowManager.shared.unregister(editorController)
                }
                document.removeWindowController(controller)
            }
            document.updateChangeCount(.changeCleared)
            document.close()
            NSDocumentController.shared.removeDocument(document)
        }
        cleanupDocuments = []
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    // MARK: - 回归：恢复必须保留文件关联

    /// 路径不可读（沙盒重启后的常态）但 bookmark 有效时，必须恢复成**文件型**文档，
    /// 标题为原文件名，而不是"未命名"。
    func testRestoreUsesBookmarkWhenPathIsUnreadable() throws {
        let originalURL = directory.appendingPathComponent("运动分类.txt")
        let text = "第一行\n第二行\n"
        try text.write(to: originalURL, atomically: true, encoding: .utf8)
        // 非沙盒宿主只能创建普通 bookmark；沙盒下为 security-scoped，解析路径一致
        let bookmark = try XCTUnwrap(try? originalURL.bookmarkData())
        let backupContentURL = directory.appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: backupContentURL, atomically: true, encoding: .utf8)
        // 故意指向不存在的位置：模拟"仅凭路径打不开原文件"
        let missingPath = directory.appendingPathComponent("missing-\(UUID().uuidString).txt").path

        let record = NPBackupRecord(
            item: NPBackupItem(backupContentURL: backupContentURL,
                               originalFileURL: URL(fileURLWithPath: missingPath),
                               cursorPosition: 0,
                               encoding: .utf8,
                               lineEnding: .lf,
                               originalFileBookmark: bookmark),
            windowGroupID: UUID(),
            tabIndex: 0,
            timestamp: Date().timeIntervalSince1970
        )

        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        appDelegate.restoreSession(from: [record])

        // 按**完整路径**匹配：测试宿主会恢复用户真实会话，可能已存在同名文件（如
        // ~/Documents/运动分类.txt），只比 lastPathComponent 会误取那一个
        let document = try XCTUnwrap(
            NSDocumentController.shared.documents
                .compactMap { $0 as? NPTextDocument }
                .first { $0.fileURL?.path == originalURL.path },
            "应恢复为文件型文档（标题即原文件名），而不是未命名文档"
        )
        cleanupDocuments.append(document)
        XCTAssertEqual(document.displayName, "运动分类.txt")
        XCTAssertEqual(document.textContent, text)
        XCTAssertFalse(document.isDocumentEdited, "内容与缓存一致时不应标脏")
    }

    // MARK: - 纯逻辑：bookmark 解析与元数据往返

    /// bookmark 无效或缺席时解析回落路径；两者皆无返回 nil。
    func testResolveFileURLFallsBackToPath() {
        let path = directory.appendingPathComponent("any.txt").path
        XCTAssertEqual(NPBackupService.resolveFileURL(path: path, bookmark: nil)?.path, path)
        XCTAssertEqual(
            NPBackupService.resolveFileURL(path: path, bookmark: Data([0x00, 0x01, 0x02]))?.path,
            path,
            "非法 bookmark 必须回落路径而不是崩/返回 nil"
        )
        XCTAssertNil(NPBackupService.resolveFileURL(path: nil, bookmark: nil))
    }

    /// 元数据可往返编解码 bookmark；旧格式（无该字段）解码为 nil。
    func testMetadataRoundTripsBookmarkAndStaysBackwardCompatible() throws {
        var metadata = NPBackupMetadata(
            schemaVersion: NPBackupService.currentSchemaVersion,
            originalFilePath: "/tmp/a.txt",
            cursorPosition: 0,
            encodingRawValue: 4,
            lineEndingRawValue: "lf",
            windowGroupID: UUID().uuidString,
            tabIndex: 0,
            timestamp: 1,
            revision: 1,
            contentHash: "hash",
            originalFileBookmark: Data([0x01, 0x02]).base64EncodedString()
        )
        let decoded = try JSONDecoder().decode(NPBackupMetadata.self,
                                               from: JSONEncoder().encode(metadata))
        XCTAssertEqual(decoded.originalFileBookmark, metadata.originalFileBookmark)

        metadata.originalFileBookmark = nil
        let withoutBookmark = try JSONDecoder().decode(NPBackupMetadata.self,
                                                       from: JSONEncoder().encode(metadata))
        XCTAssertNil(withoutBookmark.originalFileBookmark)
        XCTAssertEqual(withoutBookmark.originalFilePath, "/tmp/a.txt")
    }

    // MARK: - 回归：会话恢复由应用独占

    /// AppKit 通过 ObjC 运行时回调委托；方法名/签名写错时不会被调用（本次缺陷根因）。
    func testDelegateExposesReopenHandlerToAppKit() throws {
        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)

        XCTAssertTrue(
            appDelegate.responds(to: Selector(("applicationShouldHandleReopen:hasVisibleWindows:"))),
            "点击 Dock 重开窗口的处理必须暴露给 AppKit，否则无可见窗口时无法恢复窗口"
        )
    }

    /// 系统状态恢复会向文档控制器索取窗口；必须拒绝，否则同一文档被恢复两次。
    func testDocumentControllerRefusesSystemWindowRestoration() throws {
        let coder = try NSKeyedArchiver(requiringSecureCoding: false)
        var restoredWindow: NSWindow?
        var restoreError: Error?
        let completed = expectation(description: "restoration completion")

        NPDocumentController.restoreWindow(withIdentifier: NSUserInterfaceItemIdentifier("np-restore-test"),
                                           state: coder) { window, error in
            restoredWindow = window
            restoreError = error
            completed.fulfill()
        }

        wait(for: [completed], timeout: 5)
        XCTAssertNil(restoredWindow, "不得由系统恢复出窗口")
        XCTAssertNil(restoreError, "拒绝恢复是正常路径，不应报错")
    }

    /// 窗口不得进入系统持久状态，避免关机/登录时被 AppKit 再次恢复。
    func testWindowsAreExcludedFromSystemStateRestoration() {
        let document = NPTextDocument()
        let windowController = NPWindowFactory.makeWindowController(for: document)

        XCTAssertFalse(windowController.window?.isRestorable ?? true,
                       "会话恢复由 NPBackupService 独占，窗口必须标记为不可恢复")

        windowController.window?.close()
    }

    /// 同一文档被系统恢复和应用恢复同时装配时，只能在标签组中出现一次。
    func testAddingSameDocumentTwiceKeepsOneTab() throws {
        let document = NPTextDocument()
        let windowController = NPWindowFactory.makeWindowController(for: document)

        windowController.addTab(for: document, position: .trailing)

        XCTAssertEqual(windowController.tabBarController.count, 1)
        XCTAssertTrue(windowController.tabBarController.entries.first?.document === document)

        windowController.window?.close()
    }

    /// 一个窗口的 N 个标签必须持久化同一个窗口组，否则重启后会散成 N 个窗口。
    ///
    /// 缺陷：`registerDocument` 先按文档随机分配 `windowGroupID` 并立即落盘，
    /// `noteWindowContext`（写入真实窗口组）只改内存；异常终止（关机/登出，
    /// 不执行 `applicationShouldTerminate` 的整批刷盘）时磁盘上每个标签各持一个组
    /// ⇒ 恢复成 N 个窗口、每窗口一个标签。
    func testTabsInSameWindowPersistSingleWindowGroup() throws {
        let firstURL = directory.appendingPathComponent("tab-1.txt")
        let secondURL = directory.appendingPathComponent("tab-2.txt")
        try "1\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "2\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let first = try NPTextDocument(contentsOf: firstURL, ofType: "public.plain-text")
        let second = try NPTextDocument(contentsOf: secondURL, ofType: "public.plain-text")
        NSDocumentController.shared.addDocument(first)
        NSDocumentController.shared.addDocument(second)
        cleanupDocuments.append(contentsOf: [first, second])

        // 同一窗口的两个标签
        let windowController = NPTabWindowManager.shared.openInNewWindow(first)
        windowController.addTab(for: second, position: .trailing)
        XCTAssertEqual(windowController.tabBarController.count, 2)

        // 只等已排队写入完成，不额外触发整批刷盘：模拟异常终止时磁盘上的既有状态
        NPBackupService.shared.waitForPendingWrites()

        let paths = Set([firstURL.path, secondURL.path])
        let records = NPBackupService.shared.recoverableRecords()
            .filter { paths.contains($0.item.originalFileURL?.path ?? "") }
        XCTAssertEqual(records.count, 2, "两个标签都应有会话备份")
        XCTAssertEqual(Set(records.map(\.windowGroupID)).count, 1,
                       "同一窗口的标签必须共享同一个 windowGroupID，否则重启后会散成多个窗口")
        XCTAssertEqual(records.map(\.tabIndex).sorted(), [0, 1], "组内标签序必须持久化")
    }

    /// 文件已被其它路径打开（系统恢复/最近使用）时，会话恢复必须复用它，
    /// 否则同一文件会出现两个文档、两个标签（关机重启回归根因）。
    func testRestoreReusesDocumentAlreadyOpenForSameFile() throws {
        let fileURL = directory.appendingPathComponent("已打开.txt")
        let text = "第一行\n第二行\n"
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let existing = try NPTextDocument(contentsOf: fileURL, ofType: "public.plain-text")
        NSDocumentController.shared.addDocument(existing)
        cleanupDocuments.append(existing)
        let windowController = NPTabWindowManager.shared.openInNewWindow(existing)
        let tabCountBefore = windowController.tabBarController.count

        let backupContentURL = directory.appendingPathComponent("\(UUID().uuidString).txt")
        try text.write(to: backupContentURL, atomically: true, encoding: .utf8)
        let record = NPBackupRecord(
            item: NPBackupItem(backupContentURL: backupContentURL,
                               originalFileURL: fileURL,
                               cursorPosition: 0,
                               encoding: .utf8,
                               lineEnding: .lf,
                               originalFileBookmark: nil),
            windowGroupID: UUID(),
            tabIndex: 0,
            timestamp: Date().timeIntervalSince1970
        )

        let appDelegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        appDelegate.restoreSession(from: [record])

        let matches = NSDocumentController.shared.documents
            .compactMap { $0 as? NPTextDocument }
            .filter { $0.fileURL?.path == fileURL.path }
        XCTAssertEqual(matches.count, 1, "同一文件只能有一个文档实例")
        XCTAssertTrue(matches.first === existing, "必须复用已打开的文档，而不是新建一个")
        XCTAssertEqual(windowController.tabBarController.count, tabCountBefore,
                       "文档已在窗口显示时不得再插入标签")
    }
}
