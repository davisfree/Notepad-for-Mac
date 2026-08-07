//
//  NPBackupServiceTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPBackupService` 测试（`05_TEST_PLAN.md` UT-BACKUP-001 ~ UT-BACKUP-003）。
@MainActor
final class NPBackupServiceTests: XCTestCase {

    /// 临时备份目录（注入，避免污染真实目录）
    private var backupDirectory: URL!
    /// 被测对象（SUT，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var sut: NPBackupService!

    override func setUp() {
        super.setUp()
        backupDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-backup-tests-\(UUID().uuidString)", isDirectory: true)
        sut = NPBackupService(backupDirectory: backupDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: backupDirectory)
        backupDirectory = nil
        sut = nil
        super.tearDown()
    }

    /// 备份目录文件列表。
    private func backupFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)) ?? []
    }

    /// 首个备份内容文件的文本。
    private func backupContentText() -> String? {
        guard let name = backupFiles().first(where: { $0.hasSuffix(".txt") }) else {
            return nil
        }
        return try? String(contentsOf: backupDirectory.appendingPathComponent(name), encoding: .utf8)
    }

    /// 轮询等待条件满足（泵 RunLoop 让尾缘任务执行）。
    private func waitFor(_ seconds: TimeInterval = 3.0, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return condition()
    }

    /// UT-BACKUP-001：节流间隔 —— 连续快速编辑，尾缘写入间隔 ≤ 1s 且最终内容落盘。
    func testThrottledBackupWrite() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        XCTAssertTrue(waitFor { self.backupFiles().count == 2 }, "注册后应建立初始备份")

        let start = Date()
        document.textContent = "v1"
        document.updateChangeCount(.changeDone)
        document.textContent = "v2"
        document.updateChangeCount(.changeDone)
        XCTAssertTrue(waitFor { self.backupContentText() == "v2" }, "尾缘写入最终内容")
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(start), 1.5, "尾缘写入间隔须 ≤ 1s（含轮询粒度）")
        sut.unregisterDocument(document)
    }

    /// UT-BACKUP-002：未命名文档备份 —— recoverableItems 含未命名文档及其光标位置。
    func testUntitledDocumentBackupWithCursor() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        sut.noteCursorPosition(42, for: document)
        document.textContent = "未命名内容"
        document.updateChangeCount(.changeDone)
        XCTAssertTrue(waitFor { self.sut.recoverableItems().first?.cursorPosition == 42 },
                      "尾缘写入应包含光标位置与最终内容")

        let item = try XCTUnwrap(sut.recoverableItems().first)
        XCTAssertNil(item.originalFileURL)
        XCTAssertEqual(item.cursorPosition, 42)
        XCTAssertEqual(item.encoding, .utf8)
        XCTAssertEqual(item.lineEnding, .lf)
        XCTAssertEqual(try String(contentsOf: item.backupContentURL, encoding: .utf8), "未命名内容")
        sut.unregisterDocument(document)
    }

    /// UT-BACKUP-003：过期清理 —— 7 天前的备份被清理且不出现在 recoverableItems。
    func testExpiredBackupCleaned() throws {
        let expiredID = UUID()
        let metadata: [String: Any] = [
            "cursorPosition": 0,
            "encodingRawValue": String.Encoding.utf8.rawValue,
            "lineEndingRawValue": "\n",
            "windowGroupID": UUID().uuidString,
            "tabIndex": 0,
            "timestamp": Date().timeIntervalSince1970 - 8 * 24 * 60 * 60,
        ]
        try JSONSerialization.data(withJSONObject: metadata)
            .write(to: backupDirectory.appendingPathComponent("\(expiredID.uuidString).json"))
        try "expired".write(to: backupDirectory.appendingPathComponent("\(expiredID.uuidString).txt"),
                            atomically: true, encoding: .utf8)
        XCTAssertEqual(sut.recoverableItems().count, 1)

        sut.cleanExpiredBackups()
        XCTAssertTrue(sut.recoverableItems().isEmpty)
        XCTAssertFalse(backupFiles().contains { $0.contains(expiredID.uuidString) })
    }

    /// 正常关闭（unregister）删除备份文件。
    func testUnregisterDeletesBackup() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        XCTAssertTrue(waitFor { self.backupFiles().count == 2 })
        sut.unregisterDocument(document)
        XCTAssertTrue(backupFiles().isEmpty)
    }
}
