//
//  NPEncodingTypes.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 编码检测结果。
struct NPEncodingDetectionResult {
    /// 检测到的编码
    let encoding: String.Encoding
    /// 置信度（0.0 - 1.0）
    let confidence: Double
    /// 是否带有 BOM
    let hasBOM: Bool
}

/// 编码相关错误。
enum NPEncodingError: Error {
    /// 置信度低于阈值，无法判定编码
    case undetectable
    /// 不支持的编码
    case unsupported(String.Encoding)
    /// 编码/解码转换失败
    case conversionFailed
    /// BOM 与内容不符
    case invalidBOM
}

// MARK: - LocalizedError

extension NPEncodingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .undetectable:
            return NSLocalizedString("Error.NotPlainText",
                value: "此文件不是纯文本文件，无法打开。",
                comment: "编码检测错误：非文本")
        case .conversionFailed:
            return NSLocalizedString("Error.EncodingFailed",
                value: "编码转换失败，文件内容可能已损坏。",
                comment: "编码检测错误：转换失败")
        case .unsupported(let encoding):
            return String(format: NSLocalizedString("Error.EncodingUnsupported",
                value: "不支持的编码格式：%@。",
                comment: "编码检测错误：不支持格式"), String(describing: encoding))
        case .invalidBOM:
            return NSLocalizedString("Error.EncodingFailed",
                value: "文件 BOM 与内容不符。",
                comment: "编码检测错误：BOM 不符")
        }
    }
}

extension String.Encoding {
    /// GB18030-2000 中文编码（GBK/GB2312 的超集）。
    ///
    /// 无 `String.Encoding` 内置常量，经 CoreFoundation 编码标识构造（见 `01_TECH_SPEC.md` 3.2）。
    static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )

    /// Big5 繁体中文编码，无 `String.Encoding` 内置常量，经 CoreFoundation 编码标识构造。
    static let big5 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
    )
}
