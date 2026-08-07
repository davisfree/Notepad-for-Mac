//
//  NPColorPalette.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 复刻区域配色集中定义（`02_UI_DESIGN.md` 2.1/2.2 硬编码色值为唯一验收基准）。
///
/// 以 `NSColor(name:dynamicProvider:)` 动态颜色实现，随视图 `effectiveAppearance` 自动解析
/// （含 `NSApp.appearance` 强制主题），无需手动刷新视图。
enum NPColorPalette {

    // MARK: - 编辑区

    /// 编辑区背景（浅 #FFFFFF / 深 #1E1E1E）
    static let editorBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x1E1E1E) : NSColor.npHex(0xFFFFFF)
    }

    /// 编辑区文字（浅 #000000 / 深 #CCCCCC）
    static let editorText = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0xCCCCCC) : NSColor.npHex(0x000000)
    }

    /// 选中高亮背景（#0078D4，浅深一致；不使用系统语义色，见 02 §2.3 注意）
    static let selectionBackground = NSColor.npHex(0x0078D4)

    /// 选中高亮文字（#FFFFFF，浅深一致）
    static let selectionText = NSColor.npHex(0xFFFFFF)

    // MARK: - 查找高亮

    /// 查找匹配高亮背景（浅 #FFFF00 / 深 #7D6608，02 §5.2）
    static let findMatchBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x7D6608) : NSColor.npHex(0xFFFF00)
    }

    /// 当前匹配高亮背景（#FF8C00 橙；02 §5.2 为橙色边框，文本属性不支持边框，以橙底近似）
    static let findCurrentMatchBackground = NSColor.npHex(0xFF8C00)

    /// 当前匹配高亮文字（#FFFFFF）
    static let findCurrentMatchText = NSColor.npHex(0xFFFFFF)

    // MARK: - 状态栏

    /// 状态栏背景（浅 #F3F3F3 / 深 #2D2D2D）
    static let statusBarBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x2D2D2D) : NSColor.npHex(0xF3F3F3)
    }

    /// 状态栏文字（浅 #000000 / 深 #CCCCCC）
    static let statusBarText = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0xCCCCCC) : NSColor.npHex(0x000000)
    }

    /// 状态栏边框（浅 #E5E5E5 / 深 #3C3C3C）
    static let statusBarBorder = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x3C3C3C) : NSColor.npHex(0xE5E5E5)
    }

    /// 状态栏信息块 hover 背景（略深于状态栏背景，02 §5.4）
    static let statusBarItemHover = NSColor(name: nil) { appearance in
        appearance.npIsDark
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor.black.withAlphaComponent(0.06)
    }

    // MARK: - 查找栏

    /// 查找栏背景（浅 #F0F0F0 / 深 #2B2B2B；v1.3 修订：浅色加灰以与白色编辑区区分）
    static let findBarBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x2B2B2B) : NSColor.npHex(0xF0F0F0)
    }

    /// 查找栏边框（浅 #D1D1D1 / 深 #5F5F5F）
    static let findBarBorder = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x5F5F5F) : NSColor.npHex(0xD1D1D1)
    }

    // MARK: - 标签栏

    /// 标签栏背景（浅 #F3F3F3 / 深 #2D2D2D）
    static let tabBarBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x2D2D2D) : NSColor.npHex(0xF3F3F3)
    }

    /// 活动标签背景（浅 #FFFFFF / 深 #1E1E1E）
    static let activeTabBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x1E1E1E) : NSColor.npHex(0xFFFFFF)
    }

    /// 非活动标签背景（浅 #F3F3F3 / 深 #2D2D2D）
    static let inactiveTabBackground = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x2D2D2D) : NSColor.npHex(0xF3F3F3)
    }

    /// 标签文字·活动（浅 #000000 / 深 #FFFFFF）
    static let activeTabText = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0xFFFFFF) : NSColor.npHex(0x000000)
    }

    /// 标签文字·非活动（浅 #5F5F5F / 深 #969696）
    static let inactiveTabText = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x969696) : NSColor.npHex(0x5F5F5F)
    }

    /// 未保存指示点（浅 #0078D4 / 深 #4CC2FF）
    static let unsavedIndicator = NSColor(name: nil) { appearance in
        appearance.npIsDark ? NSColor.npHex(0x4CC2FF) : NSColor.npHex(0x0078D4)
    }
}

// MARK: - 外观判定

extension NSAppearance {
    /// 当前外观是否为深色系。
    var npIsDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

// MARK: - 十六进制颜色

extension NSColor {
    /// 以十六进制 RGB 色值创建颜色（如 `0x1E1E1E`）。
    ///
    /// 使用 sRGB 色彩空间，保证与 `02_UI_DESIGN.md` 硬编码色值逐字节一致
    /// （`calibratedRed` 为 gamma 1.8，经色彩管理转换后会产生偏差）。
    /// - Parameter rgb: 24 位 RGB 色值
    /// - Returns: 对应颜色
    static func npHex(_ rgb: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
