//
//  NPThemeManager.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 主题管理器：应用/切换浅色、深色、跟随系统（PRD FR-013）。
///
/// 主题通过设置 `NSApp.appearance` 全局生效（已开窗口即时跟随）；
/// 跟随系统时置 `nil`，由系统外观自动驱动。
@MainActor
final class NPThemeManager {

    // MARK: - 单例

    static let shared = NPThemeManager()

    // MARK: - 属性

    /// 当前生效的主题设置
    private(set) var currentTheme: NPTheme

    // MARK: - 初始化

    /// 读取偏好中的主题并应用外观（启动时调用，不发通知）。
    private init() {
        currentTheme = NPPreferences.shared.theme
        applyAppearance(for: currentTheme)
    }

    // MARK: - 主题应用

    /// 应用主题（写入偏好设置并发出 `NPThemeDidChange` 通知）。
    /// - Parameter theme: 目标主题
    func apply(theme: NPTheme) {
        currentTheme = theme
        NPPreferences.shared.theme = theme
        applyAppearance(for: theme)
        NotificationCenter.default.post(
            name: NPNotificationNames.themeDidChange,
            object: self,
            userInfo: [NPNotificationNames.themeKey: theme.rawValue]
        )
    }

    /// 将主题解析为具体的 NSAppearance（跟随系统时读取系统外观）。
    /// - Parameter theme: 目标主题
    /// - Returns: 对应外观
    func resolvedAppearance(for theme: NPTheme) -> NSAppearance? {
        switch theme {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return NSApp.effectiveAppearance
        }
    }

    // MARK: - 私有

    /// 将主题应用到应用级外观（跟随系统时置 nil，由系统自动驱动，已开窗口即时跟随）。
    /// - Parameter theme: 目标主题
    private func applyAppearance(for theme: NPTheme) {
        NSApp.appearance = theme == .system ? nil : resolvedAppearance(for: theme)
    }
}
