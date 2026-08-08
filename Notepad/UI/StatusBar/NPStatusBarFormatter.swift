//
//  NPStatusBarFormatter.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 状态栏文案格式化（纯函数，无 UI 依赖，可无 UI 测试）。
enum NPStatusBarFormatter {

    // MARK: - 行列

    /// 行列文案（`Ln 12, Col 34`，本地化 key `StatusBar.LineCol`，从 1 开始）。
    /// - Parameters:
    ///   - line: 行号
    ///   - column: 列号
    /// - Returns: 格式化文案
    static func lineColumnText(line: Int, column: Int) -> String {
        String(format: NSLocalizedString("StatusBar.LineCol", comment: "状态栏：行列"), line, column)
    }

    // MARK: - 缩放

    /// 缩放百分比文案（整数，无小数，如 `100%`；02 §3.3）。
    /// - Parameter zoomLevel: 缩放比例（1.0 = 100%）
    /// - Returns: 百分比文案
    static func zoomText(_ zoomLevel: Double) -> String {
        "\(Int((zoomLevel * 100.0).rounded()))%"
    }

    // MARK: - 字符数

    /// 统计文档字符数（排除换行符等行分隔符，对齐 Win11 状态栏行为；换行符归属行长数据）。
    /// - Parameter text: 文档文本
    /// - Returns: 非换行字符数
    static func characterCount(in text: String) -> Int {
        text.filter { !$0.isNewline }.count
    }

    /// 字符数文案（Win11 状态栏同款信息块：千分位数字 + 本地化单位，如 `1,234 characters` / `1,234 个字符`）。
    /// 数字部分按当前区域格式分组。
    /// - Parameter count: 字符数
    /// - Returns: 格式化文案
    static func characterCountText(_ count: Int) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        let numberText = numberFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return String(format: NSLocalizedString("StatusBar.CharacterCount", comment: "状态栏：字符数"), numberText)
    }

    // MARK: - 编码

    /// 编码显示名（对齐 `02_UI_DESIGN.md` 3.3 清单；`ANSI` 沿用 Win11 文案，其实现为 Windows-1252；
    /// 编码名为专有名词，各语言一致，不做本地化）。
    /// - Parameters:
    ///   - encoding: 编码
    ///   - hasBOM: 是否带 BOM
    /// - Returns: 显示名
    static func encodingName(for encoding: String.Encoding, hasBOM: Bool) -> String {
        switch encoding {
        case .utf8:
            return hasBOM ? "UTF-8 BOM" : "UTF-8"
        case .utf16LittleEndian:
            return "UTF-16 LE"
        case .utf16BigEndian:
            return "UTF-16 BE"
        case .utf32LittleEndian:
            return "UTF-32 LE"
        case .utf32BigEndian:
            return "UTF-32 BE"
        case .windowsCP1252:
            return "ANSI"
        case .gb18030:
            return "GB18030"
        case .big5:
            return "Big5"
        default:
            return String.localizedName(of: encoding)
        }
    }
}
