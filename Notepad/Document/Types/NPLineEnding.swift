//
//  NPLineEnding.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 换行符格式（rawValue 为实际换行字符）。
enum NPLineEnding: String, CaseIterable {
    case lf = "\n"      // Unix / macOS
    case crlf = "\r\n"  // Windows
    case cr = "\r"      // Macintosh

    /// 状态栏显示名称（已本地化；文案对齐 Win11 原版）。
    var displayName: String {
        switch self {
        case .lf:
            return NSLocalizedString("StatusBar.LineEnding.LF", value: "Unix (LF)", comment: "换行符：LF")
        case .crlf:
            return NSLocalizedString("StatusBar.LineEnding.CRLF", value: "Windows (CRLF)", comment: "换行符：CRLF")
        case .cr:
            return NSLocalizedString("StatusBar.LineEnding.CR", value: "Macintosh (CR)", comment: "换行符：CR")
        }
    }
}
