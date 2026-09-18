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

    /// 每次快照写入都应递增 revision，便于恢复和拒绝过期写入。
    func testBackupMetadataTracksRevision() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        document.textContent = "v1"
        document.updateChangeCount(.changeDone)

        XCTAssertTrue(waitFor {
            guard let metadataName = self.backupFiles().first(where: { $0.hasSuffix(".json") }),
                  let data = try? Data(contentsOf: self.backupDirectory.appendingPathComponent(metadataName)),
                  let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let revision = metadata["revision"] as? NSNumber else {
                return false
            }
            return revision.uint64Value >= 2
        })
        sut.unregisterDocument(document)
    }

    /// 会话标记：启动新会话前应将状态置为运行中，并返回上次是否正常退出。
    func testSessionMarkerDistinguishesCleanAndUncleanShutdown() throws {
        XCTAssertTrue(sut.beginSession(), "首次启动没有上次会话，应视为正常状态")
        XCTAssertFalse(sut.beginSession(), "未标记退出前再次启动应视为异常结束")

        sut.markCleanShutdown()
        XCTAssertTrue(sut.beginSession(), "标记正常退出后再次启动应视为正常状态")
    }

    /// 启动清理不能删除会话生命周期标记。
    func testPruneKeepsSessionState() throws {
        sut.beginSession()
        sut.pruneInvalidBackupFiles(keeping: [])
        sut.markCleanShutdown()

        XCTAssertTrue(backupFiles().contains("session-state.json"))
        XCTAssertTrue(sut.beginSession())
    }

    /// 旧版 metadata 可恢复，并在读取后补齐当前 schema 字段。
    func testLegacyMetadataMigratesOnRead() throws {
        let legacyID = UUID()
        try writeMetadata(backupID: legacyID)
        try "legacy content".write(
            to: backupDirectory.appendingPathComponent("\(legacyID.uuidString).txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(sut.recoverableItems().count, 1)
        let metadataURL = backupDirectory.appendingPathComponent("\(legacyID.uuidString).json")
        let data = try Data(contentsOf: metadataURL)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(metadata["schemaVersion"] as? Int, NPBackupService.currentSchemaVersion)
        XCTAssertEqual(metadata["revision"] as? Int, 0)
        XCTAssertNotNil(metadata["contentHash"] as? String)
    }

    /// 恢复冲突：缓存较新时使用缓存，原文件较新时保留原文件。
    func testRestoreDecisionUsesNewestSnapshot() {
        let backupDate = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(
            NPBackupService.restoreDecision(
                backupContent: "edited",
                fileContent: "original",
                backupTimestamp: backupDate.timeIntervalSince1970,
                fileModificationDate: Date(timeIntervalSince1970: 100)
            ),
            .useBackup
        )
        XCTAssertEqual(
            NPBackupService.restoreDecision(
                backupContent: "edited",
                fileContent: "original",
                backupTimestamp: 100,
                fileModificationDate: Date(timeIntervalSince1970: 200)
            ),
            .useOriginal
        )
        XCTAssertEqual(
            NPBackupService.restoreDecision(
                backupContent: "same",
                fileContent: "same",
                backupTimestamp: 100,
                fileModificationDate: Date(timeIntervalSince1970: 200)
            ),
            .useOriginal
        )
    }

    /// 超过单文档缓存上限时拒绝写入，并保留可观察错误状态。
    func testOversizedSnapshotReportsFailure() throws {
        let document = NPTextDocument()
        let notificationExpectation = expectation(description: "缓存失败通知")
        let observer = NotificationCenter.default.addObserver(
            forName: NPNotificationNames.backupDidFail,
            object: sut,
            queue: .main
        ) { notification in
            XCTAssertEqual(notification.userInfo?[NPNotificationNames.backupErrorKey] as? String,
                           "snapshotTooLarge")
            notificationExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        sut.registerDocument(document)
        document.textContent = String(repeating: "x", count: NPBackupService.maxSnapshotBytes + 1)
        document.updateChangeCount(.changeDone)

        XCTAssertTrue(waitFor { self.sut.lastBackupError == .snapshotTooLarge })
        XCTAssertEqual(self.backupContentText(), "")
        wait(for: [notificationExpectation], timeout: 1.0)
        sut.unregisterDocument(document)
    }

    /// 内容被替换后，带哈希的快照不能继续作为可恢复记录。
    func testRecoverableItemsRejectsChangedSnapshotContent() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        document.textContent = "original snapshot"
        document.updateChangeCount(.changeDone)
        XCTAssertTrue(waitFor { self.backupContentText() == "original snapshot" })

        let contentName = try XCTUnwrap(backupFiles().first(where: { $0.hasSuffix(".txt") }))
        try "tampered snapshot".write(to: backupDirectory.appendingPathComponent(contentName),
                                      atomically: true, encoding: .utf8)

        XCTAssertTrue(sut.recoverableItems().isEmpty, "内容哈希不匹配的快照不应恢复")
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

    /// 会话缓存不应覆盖原文件。
    func testBackupDoesNotWriteBackToOriginalFile() throws {
        let sourceDirectory = backupDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let originalURL = sourceDirectory.appendingPathComponent("original.txt")
        try "original".write(to: originalURL, atomically: true, encoding: .utf8)
        let document = try NPTextDocument(contentsOf: originalURL, ofType: "public.plain-text")
        sut.registerDocument(document)
        document.textContent = "edited"
        document.updateChangeCount(.changeDone)

        XCTAssertTrue(waitFor { self.backupContentText() == "edited" })
        XCTAssertEqual(try String(contentsOf: originalURL, encoding: .utf8), "original")
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

    /// 原子写入临时残留（`*.sb-*` / `*.tmp.*` 等不匹配 `<UUID>.txt/.json` 的文件名）被 prune 清除。
    func testPruneRemovesTemporaryResidue() throws {
        let residueName = "\(UUID().uuidString).txt.sb-d27de1f8-dWETIK"
        let tempResidueName = "\(UUID().uuidString).tmp.txt"
        try "residue".write(to: backupDirectory.appendingPathComponent(residueName),
                            atomically: true, encoding: .utf8)
        try "temp".write(to: backupDirectory.appendingPathComponent(tempResidueName),
                          atomically: true, encoding: .utf8)
        sut.pruneInvalidBackupFiles(keeping: [])
        XCTAssertFalse(backupFiles().contains(residueName))
        XCTAssertFalse(backupFiles().contains(tempResidueName))
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

    /// 非法快照字段：负值或损坏字段应被拒绝，防止坏恢复状态写回。
    func testRecoverableItemsRejectsInvalidSnapshotMetadata() throws {
        let invalidID = UUID()
        let metadata: [String: Any] = [
            "originalFilePath": "/tmp/invalid.txt",
            "cursorPosition": -1,
            "encodingRawValue": String.Encoding.utf8.rawValue,
            "lineEndingRawValue": "\n",
            "windowGroupID": UUID().uuidString,
            "tabIndex": -1,
            "timestamp": Date().timeIntervalSince1970
        ]
        try JSONSerialization.data(withJSONObject: metadata)
            .write(to: backupDirectory.appendingPathComponent("\(invalidID.uuidString).json"))
        try "content".write(to: backupDirectory.appendingPathComponent("\(invalidID.uuidString).txt"),
                            atomically: true, encoding: .utf8)

        XCTAssertTrue(sut.recoverableItems().isEmpty, "非法 metadata 字段应被拒绝恢复")
    }

    /// 同一原始文件的重复备份应去重：退出后重开只恢复一份标签，而不是复制出同名重复页签。
    func testRecoverableItemsDeduplicatesSameOriginalFile() throws {
        let filePath = "/tmp/reopen-dup.txt"
        let windowGroupID = UUID()
        let olderID = UUID()
        let newerID = UUID()
        let olderMetadata: [String: Any] = [
            "originalFilePath": filePath,
            "cursorPosition": 3,
            "encodingRawValue": String.Encoding.utf8.rawValue,
            "lineEndingRawValue": "\n",
            "windowGroupID": windowGroupID.uuidString,
            "tabIndex": 0,
            "timestamp": Date().timeIntervalSince1970 - 60
        ]
        let newerMetadata: [String: Any] = [
            "originalFilePath": filePath,
            "cursorPosition": 10,
            "encodingRawValue": String.Encoding.utf8.rawValue,
            "lineEndingRawValue": "\n",
            "windowGroupID": windowGroupID.uuidString,
            "tabIndex": 0,
            "timestamp": Date().timeIntervalSince1970
        ]

        try JSONSerialization.data(withJSONObject: olderMetadata)
            .write(to: backupDirectory.appendingPathComponent("\(olderID.uuidString).json"))
        try JSONSerialization.data(withJSONObject: newerMetadata)
            .write(to: backupDirectory.appendingPathComponent("\(newerID.uuidString).json"))
        try "old".write(to: backupDirectory.appendingPathComponent("\(olderID.uuidString).txt"),
                         atomically: true, encoding: .utf8)
        try "new".write(to: backupDirectory.appendingPathComponent("\(newerID.uuidString).txt"),
                         atomically: true, encoding: .utf8)

        let records = sut.recoverableRecords()
        XCTAssertEqual(records.count, 1, "同一原始文件的重复快照应保留最新一份")
        XCTAssertEqual(records[0].item.backupContentURL.lastPathComponent, "\(newerID.uuidString).txt")
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

    /// 注销后，已经排队的快照写入不能重新创建已删除的缓存。
    func testUnregisterPreventsQueuedBackupFromReappearing() throws {
        let document = NPTextDocument()
        sut.registerDocument(document)
        document.textContent = String(repeating: "queued", count: 100_000)
        document.updateChangeCount(.changeDone)
        sut.unregisterDocument(document)

        XCTAssertTrue(waitFor { self.backupFiles().isEmpty },
                      "注销后缓存必须保持删除状态")
    }

    /// 退出清理：只保留当前仍打开文档（已注册标签）的备份，删除历史关窗残留。
    func testPruneForQuitKeepsOnlyActiveDocuments() throws {
        let docA = NPTextDocument()
        let docB = NPTextDocument()
        sut.registerDocument(docA)
        sut.registerDocument(docB)
        XCTAssertTrue(waitFor { self.backupFiles().count == 4 }, "两个文档应各建立备份文件对")

        // 历史关窗残留：未注册文档的备份（detachAllTabsForWindowClose 保留的）
        let staleID = UUID()
        try writeMetadata(backupID: staleID)
        try "stale".write(to: backupDirectory.appendingPathComponent("\(staleID.uuidString).txt"),
                          atomically: true, encoding: .utf8)
        XCTAssertEqual(backupFiles().count, 6, "4 个活动文档文件 + 2 个残留文件")

        sut.pruneBackupsForQuit()

        XCTAssertFalse(backupFiles().contains { $0.contains(staleID.uuidString) },
                       "关窗残留应被清理，避免下次启动恢复出已关窗口")
        XCTAssertEqual(backupFiles().count, 4, "活动文档的备份须保留")
        sut.unregisterDocument(docA)
        sut.unregisterDocument(docB)
    }

    /// 退出清理：注册表为空（登出/关机已先行关闭窗口、文档全部摘除）时不删除任何文件，
    /// 防止误删退出时仍打开、但已由窗口关闭流程保留的备份。
    func testPruneForQuitSkipsWhenNoActiveDocuments() throws {
        let staleID = UUID()
        try writeMetadata(backupID: staleID)
        try "stale".write(to: backupDirectory.appendingPathComponent("\(staleID.uuidString).txt"),
                          atomically: true, encoding: .utf8)
        sut.pruneBackupsForQuit()
        XCTAssertEqual(backupFiles().count, 2, "注册表为空时应保守跳过，不删除任何备份")
    }
}
