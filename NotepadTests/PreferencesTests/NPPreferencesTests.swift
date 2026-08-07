//
//  NPPreferencesTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPPreferences` 测试：默认值、持久化往返、export/import、错误路径（PRD 7.1）。
@MainActor
final class NPPreferencesTests: XCTestCase {

    /// 测试套件名（独立 UserDefaults suite，避免污染 standard）
    private let suiteName = "com.notepad.tests.preferences"
    /// 测试用存储（SUT 依赖，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var testDefaults: UserDefaults!
    /// 被测对象
    private var sut: NPPreferences!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
        sut = NPPreferences(defaults: testDefaults)
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        sut = nil
        super.tearDown()
    }

    /// 默认值对齐 PRD 7.1。
    func testDefaultValues() {
        XCTAssertEqual(sut.theme, .system)
        XCTAssertEqual(sut.font.pointSize, 12.0)
        XCTAssertTrue(sut.isWordWrapEnabled)
        XCTAssertTrue(sut.isAutoSaveEnabled)
        XCTAssertEqual(sut.defaultEncoding, .utf8)
        XCTAssertEqual(sut.defaultLineEnding, .lf)
        XCTAssertTrue(sut.isStatusBarVisible)
        XCTAssertEqual(sut.defaultZoomLevel, 1.0)
    }

    /// 持久化往返：写入后新实例读取一致。
    func testPersistenceRoundTrip() {
        sut.theme = .dark
        sut.isWordWrapEnabled = false
        sut.defaultLineEnding = .crlf
        sut.defaultZoomLevel = 1.5
        sut.lastWindowFrame = NSRect(x: 100, y: 200, width: 1024, height: 768)

        let reloaded = NPPreferences(defaults: testDefaults)
        XCTAssertEqual(reloaded.theme, .dark)
        XCTAssertFalse(reloaded.isWordWrapEnabled)
        XCTAssertEqual(reloaded.defaultLineEnding, .crlf)
        XCTAssertEqual(reloaded.defaultZoomLevel, 1.5)
        XCTAssertEqual(reloaded.lastWindowFrame, NSRect(x: 100, y: 200, width: 1024, height: 768))
    }

    /// 字体序列化：family + size 持久化往返。
    func testFontPersistence() throws {
        let menlo = try XCTUnwrap(NSFont(name: "Menlo", size: 14))
        sut.font = menlo
        let reloaded = NPPreferences(defaults: testDefaults)
        XCTAssertEqual(reloaded.font.pointSize, 14.0)
    }

    /// export → import JSON round-trip 全字段一致。
    func testExportImportRoundTrip() throws {
        sut.theme = .dark
        sut.isAutoSaveEnabled = false
        sut.defaultZoomLevel = 2.0

        let data = try sut.export()
        let target = NPPreferences(defaults: testDefaults)
        target.resetToDefaults()
        try target.import(from: data)

        XCTAssertEqual(target.theme, .dark)
        XCTAssertFalse(target.isAutoSaveEnabled)
        XCTAssertEqual(target.defaultZoomLevel, 2.0)
    }

    /// 导出结构：字体为 {"family","size"}，编码为 rawValue，缩放为百分比。
    func testExportStructure() throws {
        let data = try sut.export()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let font = try XCTUnwrap(json["font"] as? [String: Any])
        XCTAssertNotNil(font["family"] as? String)
        XCTAssertNotNil(font["size"] as? NSNumber)
        XCTAssertEqual((json["defaultEncoding"] as? NSNumber)?.uintValue, String.Encoding.utf8.rawValue)
        XCTAssertEqual((json["zoomLevel"] as? NSNumber)?.doubleValue, 100.0)
    }

    /// import 损坏数据抛 `NPPreferencesError.invalidFormat`。
    func testImportInvalidDataThrows() {
        let cases: [Data] = [
            Data("not json".utf8),
            Data("[1,2,3]".utf8),
            Data("{\"theme\":\"rainbow\"}".utf8),
            Data("{\"font\":{\"size\":14}}".utf8),
        ]
        for data in cases {
            XCTAssertThrowsError(try sut.import(from: data)) { error in
                guard case NPPreferencesError.invalidFormat = error else {
                    XCTFail("期望 NPPreferencesError.invalidFormat，实际 \(error)")
                    return
                }
            }
        }
    }

    /// resetToDefaults 恢复默认值。
    func testResetToDefaults() {
        sut.theme = .dark
        sut.defaultZoomLevel = 3.0
        sut.resetToDefaults()
        XCTAssertEqual(sut.theme, .system)
        XCTAssertEqual(sut.defaultZoomLevel, 1.0)
    }
}
