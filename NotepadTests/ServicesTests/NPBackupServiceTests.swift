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

    /// 写入元数据文件（测试辅助）。
    private func writeMetadata(backupID: UUID, timestamp: TimeInterval = Date().timeIntervalSince1970) throws {
        let metadata: [String: Any] = [
            "cursorPosition": 0,
            "encodingRawValue": String.Encoding.utf8.rawValue,
            "lineEndingRawValue": "\n",
            "windowGroupID": UUID().uuidString,
            "tabIndex": 0,
            "timestamp": timestamp,
        ]
        try JSONSerialization.data(withJSONObject: metadata)
            .write(to: backupDirectory.appendingPathComponent("\(backupID.uuidString).json"))
    }

    /// UT-BACKUP-003：过期清理 —— 7 天前的备份不出现在 recoverableItems，且 prune 后文件被删除。
    func testExpiredBackupCleaned() throws {
        let expiredID = UUID()
        try writeMetadata(backupID: expiredID,
                          timestamp: Date().timeIntervalSince1970 - 8 * 24 * 60 * 60)
        try "expired".write(to: backupDirectory.appendingPathComponent("\(expiredID.uuidString).txt"),
                            atomically: true, encoding: .utf8)

        XCTAssertTrue(sut.recoverableItems().isEmpty, "过期备份不应作为有效记录加载")
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertFalse(backupFiles().contains { $0.contains(expiredID.uuidString) })
    }

    /// 原子写入临时残留（`*.sb-*` 等不匹配 `<UUID>.txt/.json` 的文件名）被 prune 清除。
    func testPruneRemovesTemporaryResidue() throws {
        let residueName = "\(UUID().uuidString).txt.sb-d27de1f8-dWETIK"
        try "residue".write(to: backupDirectory.appendingPathComponent(residueName),
                            atomically: true, encoding: .utf8)
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertFalse(backupFiles().contains(residueName))
    }

    /// 孤儿 `.json`（无对应 `.txt`）：不作为有效记录，prune 后删除。
    func testPruneRemovesOrphanMetadata() throws {
        let orphanID = UUID()
        try writeMetadata(backupID: orphanID)
        XCTAssertTrue(sut.recoverableItems().isEmpty)
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertTrue(backupFiles().isEmpty)
    }

    /// 孤儿 `.txt`（无对应 `.json`）被 prune 清除。
    func testPruneRemovesOrphanContent() throws {
        try "orphan".write(to: backupDirectory.appendingPathComponent("\(UUID().uuidString).txt"),
                           atomically: true, encoding: .utf8)
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertTrue(backupFiles().isEmpty)
    }

    /// 元数据损坏（非法 JSON）的记录：不作为有效记录，prune 后文件对删除。
    func testPruneRemovesCorruptMetadata() throws {
        let corruptID = UUID()
        try "not json".write(to: backupDirectory.appendingPathComponent("\(corruptID.uuidString).json"),
                             atomically: true, encoding: .utf8)
        try "content".write(to: backupDirectory.appendingPathComponent("\(corruptID.uuidString).txt"),
                            atomically: true, encoding: .utf8)
        XCTAssertTrue(sut.recoverableItems().isEmpty)
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertTrue(backupFiles().isEmpty)
    }

    /// 有效文件对：加载为有效记录，prune（以其标识为白名单）后保留。
    func testPruneKeepsValidPair() throws {
        let validID = UUID()
        try writeMetadata(backupID: validID)
        try "valid".write(to: backupDirectory.appendingPathComponent("\(validID.uuidString).txt"),
                          atomically: true, encoding: .utf8)
        XCTAssertEqual(sut.recoverableItems().count, 1)
        sut.pruneInvalidBackupFiles(keeping: [validID])
        XCTAssertEqual(backupFiles().count, 2)
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
