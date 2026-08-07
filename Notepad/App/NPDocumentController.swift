//
//  NPDocumentController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-03.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// 自定义文档控制器。
///
/// 显式提供「文档类型 → NSDocument 子类」的映射。
///
/// 背景：macOS 26 上经 `swiftc` 直编（非 xcodebuild）的 bundle，
/// `NSDocumentController.documentClass(forType:)` 无法解析 Info.plist 中
/// `NSDocumentClass` 声明的类（启动弹窗"未能创建文稿"），尽管
/// `NSClassFromString("Notepad.NPTextDocument")` 可以正常找到该类。
/// 按 Apple 文档，子类实例在首次创建时成为 shared controller，
/// 因此只需在 App 启动早期实例化一次即可全局生效。
///
/// 文件类型策略（v1.4 修订）：不按扩展名/UTI 预筛选，**尝试打开任意文件**，
/// 是否为纯文本由编码检测（`NPEncodingManager.detect`）在 `read(from:)` 时判定：
/// 二进制内容 → `NPEncodingError.undetectable` → 用户友好提示，符合 PRD FR-001
/// "支持打开任意扩展名的纯文本文件" 的完整语义。
@MainActor
final class NPDocumentController: NSDocumentController {

    /// 返回文档类型对应的文档类。
    ///
    /// 全部类型映射为 `NPTextDocument`——编码检测在 `read(from:ofType:)` 中
    /// 判定文件是否为可读纯文本，非文本内容抛 `NPEncodingError` 并由
    /// `LocalizedError` 提供中文提示。
    /// - Parameter typeName: 文档类型 UTI
    /// - Returns: `NPTextDocument`（全部类型）
    override func documentClass(forType typeName: String) -> AnyClass? {
        return NPTextDocument.self
    }

    /// 打开面板过滤类型：不预筛选，任意文件均可选（Windows 记事本行为）。
    ///
    /// 不调 `super.runModalOpenPanel`：其内部会按传入类型重置面板过滤；
    /// 直接 `runModal` 契约等价（模态显示 + 返回结果码，选中文件由 `openPanel.URLs` 读取）。
    /// - Parameters:
    ///   - openPanel: 打开面板
    ///   - types: 系统按 Info.plist 收集的类型列表（本类不依赖）
    /// - Returns: 模态结果
    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        openPanel.allowsOtherFileTypes = true
        return openPanel.runModal().rawValue
    }
}
