//
//  NPError.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 业务通用错误。
///
/// 按 `04_MODULE_API.md` 0.4 约定，各模块可恢复错误集中定义于此；
/// 模块专属错误定义在各自的 Types 文件中（如 `NPEncodingError`）。
enum NPError: Error {
    /// 不支持的文档类型（预留给文档类型校验；当前 `NPTextDocument` 按纯文本处理任意输入）
    case unsupportedDocumentType(String)
    /// 只读文档不允许保存（大文件只读模式，PRD FR-001）
    case documentIsReadOnly
}
