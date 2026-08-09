//
//  NPLanguage.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

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

// MARK: - 语言切换（设置面板入口；原应用菜单"显示语言"动作逻辑抽取）

extension NPLanguage {

    /// 应用显示语言：写偏好、同步 `AppleLanguages` 并提示"重启后生效"。
    ///
    /// `.system` 移除此前写入的 `AppleLanguages` 覆盖键，使界面语言回落为系统语言。
    /// - Parameters:
    ///   - language: 目标语言
    ///   - preferences: 偏好存储（测试注入独立 suite 的实例）
    ///   - window: 重启提示 sheet 的宿主窗口；为 nil 时跳过提示（无窗口环境/单元测试）
    @MainActor
    static func apply(_ language: NPLanguage, to preferences: NPPreferences = .shared,
                      window: NSWindow? = nil) {
        guard preferences.displayLanguage != language else {
            return
        }
        preferences.displayLanguage = language
        // 切换时同步写/移除 AppleLanguages（启动时 AppDelegate.init 也会同步一次，此处确保"立即重启"
        // 的新进程在 Foundation 语言解析前就能读到新值，否则界面语言会比勾选晚一次重启生效）。
        // `.system` 无覆盖值：移除此前写入的键，使界面语言回落为系统语言。
        if let languages = language.appleLanguagesValue {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize() // 保证重启前落盘
        guard let window else {
            return
        }
        presentRestartAlert(window: window)
    }

    /// 显示语言切换提示：重启后生效，提供"立即重启 / 稍后"。
    /// - Parameter window: sheet 宿主窗口
    @MainActor
    private static func presentRestartAlert(window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Language.RestartRequired.Title",
                                              comment: "显示语言：重启提示标题")
        alert.informativeText = NSLocalizedString("Language.RestartRequired.Message",
                                                  comment: "显示语言：重启提示内容")
        alert.alertStyle = .informational
        alert.addButton(withTitle: NSLocalizedString("Language.RestartNow",
                                                     comment: "显示语言：立即重启"))
        alert.addButton(withTitle: NSLocalizedString("Language.RestartLater",
                                                     comment: "显示语言：稍后"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                relaunchApplication()
            }
        }
    }

    /// 经 `open` 重启应用：以 `-n` 启动独立新实例，待启动请求提交完成后再终止当前进程。
    ///
    /// 不带 `-n` 时，`open` 在应用仍处于运行状态（退出流程尚未结束）的情况下会把请求
    /// 路由到现有实例，表现为"退出了但没重启"；`-n` 强制创建新实例，避免该竞态。
    /// 通过 `terminationHandler` 等 `open` 进程结束（LaunchServices 已提交启动请求）
    /// 才终止当前进程，防止"先退出、新实例未启动"的窗口；`open` 启动失败则不退出。
    @MainActor
    private static func relaunchApplication() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundleURL.path]
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
        do {
            try process.run()
        } catch {
            // `open` 无法启动：保持当前进程运行，避免"退出不重启"
        }
    }
}
