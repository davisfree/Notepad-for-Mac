//
//  NPHelpContentTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-21.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPHelpContent` 测试（帮助 → 查看帮助，PRD 4.1）。
final class NPHelpContentTests: XCTestCase {

    /// 临时目录（每个用例独立，tearDown 清理）。
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NPHelpContentTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    /// 资源存在且非空时加载成功（构造含 Contents/Resources 布局的伪 Bundle）。
    func testLoadsMarkdownFromBundle() throws {
        let bundle = try makeBundle(markdown: "# 帮助\n\n正文。")
        let markdown = try XCTUnwrap(NPHelpContent.loadMarkdown(bundle: bundle))
        XCTAssertTrue(markdown.contains("# 帮助"))
        XCTAssertTrue(markdown.contains("正文。"))
    }

    /// 资源内容为空白时视为不可用，返回 nil。
    func testReturnsNilForEmptyContent() throws {
        let bundle = try makeBundle(markdown: "  \n\n")
        XCTAssertNil(NPHelpContent.loadMarkdown(bundle: bundle))
    }

    /// Bundle 缺少帮助资源时返回 nil（窗口据此显示占位文案）。
    func testReturnsNilWhenResourceMissing() {
        // 单测 target 的 Bundle 不含 Help.md
        XCTAssertNil(NPHelpContent.loadMarkdown(bundle: Bundle(for: Self.self)))
    }

    // MARK: - 私有

    /// 在临时目录构造最小可用 Bundle（Contents/Info.plist + Contents/Resources/Help.md）。
    /// - Parameter markdown: 写入 Help.md 的内容
    /// - Returns: 伪 Bundle
    private func makeBundle(markdown: String) throws -> Bundle {
        let bundleURL = tempDirectory.appendingPathComponent("Fake.bundle", isDirectory: true)
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try Data("<?xml version=\"1.0\"?><plist version=\"1.0\"><dict/>".utf8)
            .write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        try Data(markdown.utf8)
            .write(to: resourcesURL.appendingPathComponent("\(NPHelpContent.resourceName).\(NPHelpContent.resourceExtension)"))
        return try XCTUnwrap(Bundle(url: bundleURL))
    }
}
