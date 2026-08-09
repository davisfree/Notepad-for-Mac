//
//  NPPreferencesPanelTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-08.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// 偏好设置面板测试：控件初值反映偏好、控件动作写回并持久化、
/// 语言切换写 `AppleLanguages`、`resetToDefaults` 后控件回默认。
@MainActor
final class NPPreferencesPanelTests: XCTestCase {

    /// 测试套件名（独立 UserDefaults suite，避免污染 standard）
    private let suiteName = "com.notepad.tests.preferences-panel"
    /// 测试用存储（SUT 依赖，测试内允许直接解包，见 08 §2 测试豁免说明）
    private var testDefaults: UserDefaults!
    /// 被测偏好
    private var preferences: NPPreferences!
    /// 通用页
    private var generalVC: NPGeneralPreferencesViewController!
    /// 编辑器页
    private var editorVC: NPEditorPreferencesViewController!
    /// 测试前 standard 的 AppleLanguages 原值（tearDown 恢复，避免污染环境）
    private var savedAppleLanguages: Any?

    override func setUp() {
        super.setUp()
        savedAppleLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
        testDefaults = UserDefaults(suiteName: suiteName)
        testDefaults.removePersistentDomain(forName: suiteName)
        preferences = NPPreferences(defaults: testDefaults)
        generalVC = NPGeneralPreferencesViewController(preferences: preferences)
        editorVC = NPEditorPreferencesViewController(preferences: preferences)
        // 强制装载视图（控件在 loadView 中装配）
        _ = generalVC.view
        _ = editorVC.view
    }

    override func tearDown() {
        if let savedAppleLanguages {
            UserDefaults.standard.set(savedAppleLanguages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        testDefaults.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        preferences = nil
        generalVC = nil
        editorVC = nil
        savedAppleLanguages = nil
        super.tearDown()
    }

    // MARK: - 初值

    /// 通用页控件初值反映偏好。
    func testGeneralControlsReflectPreferences() {
        preferences.displayLanguage = .simplifiedChinese
        preferences.theme = .dark
        preferences.isAutoSaveEnabled = false
        preferences.isStatusBarVisible = false

        let viewController = NPGeneralPreferencesViewController(preferences: preferences)
        _ = viewController.view

        XCTAssertEqual(viewController.languagePopup.selectedItem?.representedObject as? String,
                       NPLanguage.simplifiedChinese.rawValue)
        XCTAssertEqual(viewController.themePopup.selectedItem?.representedObject as? String,
                       NPTheme.dark.rawValue)
        XCTAssertEqual(viewController.autoSaveCheckbox.state, .off)
        XCTAssertEqual(viewController.statusBarCheckbox.state, .off)
    }

    /// 编辑器页控件初值反映偏好。
    func testEditorControlsReflectPreferences() {
        preferences.isWordWrapEnabled = false
        preferences.defaultEncoding = .gb18030
        preferences.defaultLineEnding = .crlf
        preferences.defaultZoomLevel = 1.5

        let viewController = NPEditorPreferencesViewController(preferences: preferences)
        _ = viewController.view

        XCTAssertEqual(viewController.wordWrapCheckbox.state, .off)
        XCTAssertEqual((viewController.encodingPopup.selectedItem?.representedObject as? NSNumber)?.uintValue,
                       String.Encoding.gb18030.rawValue)
        XCTAssertEqual(viewController.lineEndingPopup.selectedItem?.representedObject as? String,
                       NPLineEnding.crlf.rawValue)
        XCTAssertEqual((viewController.zoomPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue, 1.5)
    }

    // MARK: - 写回

    /// 通用页控件动作写回偏好并持久化到注入的 defaults。
    func testGeneralControlsWriteBackAndPersist() {
        selectItem(in: generalVC.languagePopup, rawValue: NPLanguage.english.rawValue)
        generalVC.languageDidChange(generalVC.languagePopup)
        selectItem(in: generalVC.themePopup, rawValue: NPTheme.light.rawValue)
        generalVC.themeDidChange(generalVC.themePopup)
        generalVC.autoSaveCheckbox.state = .off
        generalVC.autoSaveDidChange(generalVC.autoSaveCheckbox)
        generalVC.statusBarCheckbox.state = .off
        generalVC.statusBarDidChange(generalVC.statusBarCheckbox)

        XCTAssertEqual(preferences.displayLanguage, .english)
        XCTAssertEqual(preferences.theme, .light)
        XCTAssertFalse(preferences.isAutoSaveEnabled)
        XCTAssertFalse(preferences.isStatusBarVisible)
        // 持久化到注入的 suite（新实例读回一致）
        let reloaded = NPPreferences(defaults: testDefaults)
        XCTAssertEqual(reloaded.displayLanguage, .english)
        XCTAssertEqual(reloaded.theme, .light)
        XCTAssertFalse(reloaded.isAutoSaveEnabled)
        XCTAssertFalse(reloaded.isStatusBarVisible)
    }

    /// 语言切换同步写 `AppleLanguages`（重启后生效的载体）。
    func testLanguageChangeWritesAppleLanguages() {
        selectItem(in: generalVC.languagePopup, rawValue: NPLanguage.english.rawValue)
        generalVC.languageDidChange(generalVC.languagePopup)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "AppleLanguages"), ["en"])
    }

    /// 编辑器页控件动作写回偏好并持久化到注入的 defaults。
    func testEditorControlsWriteBackAndPersist() {
        editorVC.wordWrapCheckbox.state = .off
        editorVC.wordWrapDidChange(editorVC.wordWrapCheckbox)
        selectItem(in: editorVC.encodingPopup, rawValue: NSNumber(value: String.Encoding.big5.rawValue))
        editorVC.encodingDidChange(editorVC.encodingPopup)
        selectItem(in: editorVC.lineEndingPopup, rawValue: NPLineEnding.cr.rawValue)
        editorVC.lineEndingDidChange(editorVC.lineEndingPopup)
        selectItem(in: editorVC.zoomPopup, rawValue: NSNumber(value: 2.0))
        editorVC.zoomDidChange(editorVC.zoomPopup)

        XCTAssertFalse(preferences.isWordWrapEnabled)
        XCTAssertEqual(preferences.defaultEncoding, .big5)
        XCTAssertEqual(preferences.defaultLineEnding, .cr)
        XCTAssertEqual(preferences.defaultZoomLevel, 2.0)
        // 持久化到注入的 suite（新实例读回一致）
        let reloaded = NPPreferences(defaults: testDefaults)
        XCTAssertFalse(reloaded.isWordWrapEnabled)
        XCTAssertEqual(reloaded.defaultEncoding, .big5)
        XCTAssertEqual(reloaded.defaultLineEnding, .cr)
        XCTAssertEqual(reloaded.defaultZoomLevel, 2.0)
    }

    /// 字体面板回传（changeFont:）写回偏好。
    func testChangeFontWritesBack() throws {
        let menlo = try XCTUnwrap(NSFont(name: "Menlo", size: 14))
        let fontManager = NSFontManager.shared
        let panel = NSFontPanel.shared
        panel.setPanelFont(menlo, isMultiple: false)
        fontManager.setSelectedFont(menlo, isMultiple: false)
        // 模拟字体面板确认（记录"经面板转换"，与真实点击路径一致）
        fontManager.modifyFontViaPanel(panel)
        editorVC.changeFont(fontManager)

        XCTAssertEqual(preferences.font.fontName, menlo.fontName)
        // 持久化到注入的 suite（新实例读回字族一致）
        let reloaded = NPPreferences(defaults: testDefaults)
        XCTAssertEqual(reloaded.font.familyName, "Menlo")
        // 字体展示文案经通知异步刷新
        pumpMainActor()
        XCTAssertTrue(editorVC.fontTextField.stringValue.contains("Menlo"))
    }

    // MARK: - 恢复默认

    /// resetToDefaults 后两页控件回默认（经 preferencesDidChange 通知刷新）。
    func testResetToDefaultsRefreshesControls() {
        preferences.isAutoSaveEnabled = false
        preferences.isStatusBarVisible = false
        preferences.isWordWrapEnabled = false
        preferences.defaultEncoding = .big5
        preferences.defaultLineEnding = .crlf
        preferences.defaultZoomLevel = 2.0
        pumpMainActor()
        XCTAssertEqual(generalVC.autoSaveCheckbox.state, .off)

        preferences.resetToDefaults()
        pumpMainActor()

        XCTAssertEqual(generalVC.autoSaveCheckbox.state, .on)
        XCTAssertEqual(generalVC.statusBarCheckbox.state, .on)
        XCTAssertEqual(generalVC.languagePopup.selectedItem?.representedObject as? String,
                       NPLanguage.system.rawValue)
        XCTAssertEqual(generalVC.themePopup.selectedItem?.representedObject as? String,
                       NPTheme.system.rawValue)
        XCTAssertEqual(editorVC.wordWrapCheckbox.state, .on)
        XCTAssertEqual((editorVC.encodingPopup.selectedItem?.representedObject as? NSNumber)?.uintValue,
                       String.Encoding.utf8.rawValue)
        XCTAssertEqual(editorVC.lineEndingPopup.selectedItem?.representedObject as? String,
                       NPLineEnding.lf.rawValue)
        XCTAssertEqual((editorVC.zoomPopup.selectedItem?.representedObject as? NSNumber)?.doubleValue, 1.0)
    }

    // MARK: - 私有

    /// 按 representedObject 选中弹出菜单项（不触发 action，动作由测试显式调用）。
    /// - Parameters:
    ///   - popup: 弹出菜单
    ///   - rawValue: 目标项 representedObject
    private func selectItem(in popup: NSPopUpButton, rawValue: Any) {
        let index = popup.itemArray.firstIndex { item in
            switch (item.representedObject, rawValue) {
            case let (lhs as String, rhs as String):
                return lhs == rhs
            case let (lhs as NSNumber, rhs as NSNumber):
                return lhs == rhs
            default:
                return false
            }
        }
        popup.selectItem(at: index ?? NSNotFound)
        XCTAssertNotEqual(index, nil, "弹出菜单中未找到 \(rawValue)")
    }

    /// 抽干主线程队列：控件刷新经 `Task { @MainActor in ... }` 异步执行，
    /// 排一个在其后的任务并等待，即保证刷新已完成。
    private func pumpMainActor() {
        let drained = expectation(description: "主线程刷新完成")
        Task { @MainActor in
            drained.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}
