//
//  NPLanguage.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 显示语言设置（App 内界面语言，独立于系统语言）。
///
/// `.system` 跟随系统首选语言；其余枚举项对应 `knownRegions` 中的本地化资源。
/// 选择后经 `appleLanguagesValue` 覆盖 `AppleLanguages` 偏好，**重启后生效**。
enum NPLanguage: String, CaseIterable {
    /// 跟随系统
    case system = "system"
    /// 英语
    case english = "en"
    /// 简体中文
    case simplifiedChinese = "zh-Hans"
    /// 繁体中文
    case traditionalChinese = "zh-Hant"

    /// 菜单显示名：语言名跟随界面语言本地化显示（如中文界面"英文"，英文界面 "English"）。
    var displayName: String {
        switch self {
        case .system:
            return NSLocalizedString("Menu.App.Language.System", value: "System",
                                     comment: "显示语言：跟随系统")
        case .english:
            return NSLocalizedString("Menu.App.Language.English", value: "English",
                                     comment: "显示语言：英文")
        case .simplifiedChinese:
            return NSLocalizedString("Menu.App.Language.ZhHans", value: "Simplified Chinese",
                                     comment: "显示语言：简体中文")
        case .traditionalChinese:
            return NSLocalizedString("Menu.App.Language.ZhHant", value: "Traditional Chinese",
                                     comment: "显示语言：繁体中文")
        }
    }

    /// 写入 `AppleLanguages` 的值（`.system` 返回 nil，交由系统语言决定）。
    var appleLanguagesValue: [String]? {
        switch self {
        case .system:
            return nil
        case .english:
            return ["en"]
        case .simplifiedChinese:
            return ["zh-Hans"]
        case .traditionalChinese:
            return ["zh-Hant"]
        }
    }
}
