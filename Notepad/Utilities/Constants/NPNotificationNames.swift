//
//  NPNotificationNames.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 通知名称与 userInfo 键常量（`04_MODULE_API.md` 6.1）。
///
/// 桥接规则：`userInfo` 为 `[AnyHashable: Any]`，值一律以 rawValue 传递——
/// `String.Encoding` → `NSNumber(rawValue: UInt)`；`NPLineEnding` / `NPTheme` → `String(rawValue)`；
/// 缩放 → `NSNumber(Double)`。
enum NPNotificationNames {

    // MARK: - 通知名称

    /// 文档编码发生变化（发出者：NPTextDocument）
    static let documentEncodingDidChange = Notification.Name("NPDocumentEncodingDidChange")

    /// 文档换行符发生变化（发出者：NPTextDocument）
    static let documentLineEndingDidChange = Notification.Name("NPDocumentLineEndingDidChange")

    /// 主题发生变化（发出者：NPThemeManager）
    static let themeDidChange = Notification.Name("NPThemeDidChange")

    /// 缩放比例发生变化（发出者：NPEditorView）
    static let zoomLevelDidChange = Notification.Name("NPZoomLevelDidChange")

    /// 偏好设置发生变化（发出者：NPPreferences）
    static let preferencesDidChange = Notification.Name("NPPreferencesDidChange")

    // MARK: - userInfo 键

    /// `NSNumber`，值为 `String.Encoding.rawValue`
    static let encodingKey = "encoding"
    /// `String`，值为 `NPLineEnding.rawValue`
    static let lineEndingKey = "lineEnding"
    /// `String`，值为 `NPTheme.rawValue`
    static let themeKey = "theme"
    /// `NSNumber`，值为 `Double`（1.0 = 100%）
    static let zoomLevelKey = "zoomLevel"
}
