//
//  NPLanguageTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPLanguage` 测试：枚举完整性、AppleLanguages 映射、显示名非空。
@MainActor
final class NPLanguageTests: XCTestCase {

    /// 枚举覆盖全部语言项（4 项：跟随系统 / en / zh-Hans / zh-Hant）。
    func testAllCases() {
        XCTAssertEqual(NPLanguage.allCases, [.system, .english, .simplifiedChinese, .traditionalChinese])
    }

    /// AppleLanguages 映射：system → nil（不覆盖），其余 → 对应语言码。
    func testAppleLanguagesValue() {
        XCTAssertNil(NPLanguage.system.appleLanguagesValue)
        XCTAssertEqual(NPLanguage.english.appleLanguagesValue, ["en"])
        XCTAssertEqual(NPLanguage.simplifiedChinese.appleLanguagesValue, ["zh-Hans"])
        XCTAssertEqual(NPLanguage.traditionalChinese.appleLanguagesValue, ["zh-Hant"])
    }

    /// 显示名非空（语言名使用自名，"跟随系统"经本地化）。
    func testDisplayNameNotEmpty() {
        for language in NPLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty, "\(language.rawValue) 显示名不应为空")
        }
    }
}
