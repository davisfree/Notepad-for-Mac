//
//  NPHelpContent.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-21.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 帮助内容加载器（帮助 → 查看帮助，PRD 4.1）。
///
/// 帮助正文为随包分发的本地化 Markdown 资源（`Resources/<locale>.lproj/Help.md`），
/// 按系统/应用显示语言由 Bundle 本地化解析；与 `NPFeedbackComposer` 同为纯加载逻辑，
/// Bundle 可注入以便单元测试。
enum NPHelpContent {

    /// 帮助资源文件名（不含扩展名）
    static let resourceName = "Help"

    /// 帮助资源扩展名
    static let resourceExtension = "md"

    /// 加载本地化帮助文本（Markdown）。
    /// - Parameter bundle: 资源所在 Bundle（默认主 Bundle，测试可注入）
    /// - Returns: 帮助文本；资源缺失、读取失败或内容为空时为 nil
    static func loadMarkdown(bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
