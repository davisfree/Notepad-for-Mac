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
    /// 本测试恢复出的文档（tearDown 清理，避免污染其它用例）
    private var restoredDocument: NPTextDocument?

    override func setUp() {
        super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("np-restore-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let restoredDocument {
            NPBackupService.shared.unregisterDocument(restoredDocument)
            for controller in restoredDocument.windowControllers {
                restoredDocument.removeWindowController(controller)
            }
            restoredDocument.updateChangeCount(.changeCleared)
            restoredDocument.close()
            NSDocumentController.shared.removeDocument(restoredDocument)
        }
        restoredDocument = nil
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

        let document = try XCTUnwrap(
            NSDocumentController.shared.documents
                .compactMap { $0 as? NPTextDocument }
                .first { $0.fileURL?.lastPathComponent == "运动分类.txt" },
            "应恢复为文件型文档（标题即原文件名），而不是未命名文档"
        )
        restoredDocument = document
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
}
