//
//  NPLineEndingManager.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 换行符检测与转换（静态纯函数，无状态、无副作用）。
enum NPLineEndingManager {

    // MARK: - 检测

    /// 检测文本中的换行符格式（以出现频次最高的为准，无换行时返回系统默认 LF）。
    ///
    /// 统计规则：CRLF 成对计数（不重复计入 CR/LF），独立的 CR、LF 单独计数。
    /// 数量相同时按 CRLF > LF > CR 的优先级取舍，保证结果确定。
    /// - Parameter text: 文本内容
    /// - Returns: 检测到的换行符格式
    static func detect(in text: String) -> NPLineEnding {
        var crlfCount = 0
        var lfCount = 0
        var crCount = 0
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                crCount += 1
                previousWasCR = true
            case "\n":
                if previousWasCR {
                    // 与前面的 CR 配对为 CRLF，撤销 CR 计数
                    crCount -= 1
                    crlfCount += 1
                } else {
                    lfCount += 1
                }
                previousWasCR = false
            default:
                previousWasCR = false
            }
        }
        if crlfCount == 0, lfCount == 0, crCount == 0 {
            return .lf
        }
        if crlfCount >= lfCount, crlfCount >= crCount {
            return .crlf
        }
        if lfCount >= crCount {
            return .lf
        }
        return .cr
    }

    // MARK: - 转换

    /// 将文本中的换行符统一转换为目标格式（先归一为 LF 再转目标格式，可处理混合换行）。
    /// - Parameters:
    ///   - text: 文本内容
    ///   - lineEnding: 目标换行符格式
    /// - Returns: 转换后的文本
    static func normalize(_ text: String, to lineEnding: NPLineEnding) -> String {
        let unified = text
            .replacingOccurrences(of: NPLineEnding.crlf.rawValue, with: NPLineEnding.lf.rawValue)
            .replacingOccurrences(of: NPLineEnding.cr.rawValue, with: NPLineEnding.lf.rawValue)
        guard lineEnding != .lf else {
            return unified
        }
        return unified.replacingOccurrences(of: NPLineEnding.lf.rawValue, with: lineEnding.rawValue)
    }
}
