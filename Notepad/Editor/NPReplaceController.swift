//
//  NPReplaceController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 替换逻辑控制器（无 UI 依赖）。
final class NPReplaceController {

    // MARK: - 初始化

    init() {}

    // MARK: - 替换

    /// 替换单个匹配，返回新文本。
    /// - Parameters:
    ///   - range: 待替换范围（UTF-16 偏移）
    ///   - text: 原始文本
    ///   - replacement: 替换内容
    /// - Returns: 替换后的新文本；范围无效时返回原文本
    func replacing(_ range: NSRange, in text: String, with replacement: String) -> String {
        guard let swiftRange = Range(range, in: text) else {
            return text
        }
        return text.replacingCharacters(in: swiftRange, with: replacement)
    }

    /// 替换全部匹配（从后往前替换，避免前面替换引起的范围偏移）。
    /// - Parameters:
    ///   - matches: 全部匹配范围（基于 `text` 的 UTF-16 偏移）
    ///   - text: 原始文本
    ///   - replacement: 替换内容
    /// - Returns: 新文本与替换次数
    func replacingAll(matches: [NSRange], in text: String, with replacement: String) -> (text: String, count: Int) {
        var result = text
        var count = 0
        for range in matches.sorted(by: { lhs, rhs in lhs.location > rhs.location }) {
            guard let swiftRange = Range(range, in: result) else {
                continue
            }
            result.replaceSubrange(swiftRange, with: replacement)
            count += 1
        }
        return (result, count)
    }
}
