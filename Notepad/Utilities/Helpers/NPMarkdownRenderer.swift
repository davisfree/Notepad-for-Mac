//
//  NPMarkdownRenderer.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-21.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 极简 Markdown 渲染器（帮助窗口专用）。
///
/// `AttributedString(markdown:)` 只产出 `presentationIntent` 语义属性，
/// AppKit `NSTextView` 不会将其解析为字体样式（帮助正文会显示为无格式纯文本），
/// 故自行实现行级 + 行内渲染，直接产出真实字体/颜色属性。
/// 支持子集：`#`/`##`/`###` 标题、`-` 列表、`**加粗**`、`` `行内代码` ``。
/// 纯函数、无全局状态，可无 UI 测试。
enum NPMarkdownRenderer {

    /// 正文字号
    static let bodyFontSize: CGFloat = 13

    /// 各级标题字号（一级 → 三级）
    private static let headingFontSizes: [CGFloat] = [20, 16, 14]

    /// 标题段前间距
    private static let headingSpacingBefore: CGFloat = 14
    /// 标题段后间距
    private static let headingSpacingAfter: CGFloat = 6
    /// 正文段后间距
    private static let paragraphSpacingAfter: CGFloat = 8
    /// 列表项段后间距
    private static let listItemSpacingAfter: CGFloat = 4
    /// 列表项悬挂缩进
    private static let listItemIndent: CGFloat = 14

    /// 将 Markdown 渲染为属性字符串（颜色用语义 label 色，深浅色自适应）。
    /// - Parameter markdown: Markdown 源文本
    /// - Returns: 属性字符串
    static func render(markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var isFirstBlock = true
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                continue // 空行的分隔作用由段落间距承担
            }
            append(parseBlock(trimmed), isFirst: isFirstBlock, to: output)
            isFirstBlock = false
        }
        return output
    }

    // MARK: - 私有

    /// 行级块类型。
    private enum Block {
        /// 标题（level 1–3）
        case heading(level: Int, text: String)
        /// 列表项
        case listItem(text: String)
        /// 普通段落
        case paragraph(text: String)
    }

    /// 解析一行文本为块。
    /// - Parameter line: 已去除首尾空白的非空行
    /// - Returns: 块
    private static func parseBlock(_ line: String) -> Block {
        var rest = line
        var level = 0
        while rest.hasPrefix("#") {
            level += 1
            rest = String(rest.dropFirst())
        }
        if level > 0, rest.hasPrefix(" ") {
            return .heading(level: min(level, headingFontSizes.count), text: String(rest.dropFirst()))
        }
        if line.hasPrefix("- ") {
            return .listItem(text: String(line.dropFirst(2)))
        }
        return .paragraph(text: line)
    }

    /// 渲染一个块并追加到输出（含结尾换行与段落样式）。
    /// - Parameters:
    ///   - block: 块
    ///   - isFirst: 是否为首个块（首个标题不设段前间距）
    ///   - output: 输出
    private static func append(_ block: Block, isFirst: Bool, to output: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        let baseFont: NSFont
        let text: String
        switch block {
        case .heading(let level, let headingText):
            baseFont = NSFont.boldSystemFont(ofSize: headingFontSizes[level - 1])
            style.paragraphSpacingBefore = isFirst ? 0 : headingSpacingBefore
            style.paragraphSpacing = headingSpacingAfter
            text = headingText
        case .listItem(let itemText):
            baseFont = NSFont.systemFont(ofSize: bodyFontSize)
            style.paragraphSpacing = listItemSpacingAfter
            style.headIndent = listItemIndent
            text = "•  " + itemText
        case .paragraph(let paragraphText):
            baseFont = NSFont.systemFont(ofSize: bodyFontSize)
            style.paragraphSpacing = paragraphSpacingAfter
            text = paragraphText
        }
        let start = output.length
        appendInline(text, baseFont: baseFont, to: output)
        output.append(NSAttributedString(string: "\n", attributes: [.font: baseFont]))
        output.addAttribute(.paragraphStyle, value: style,
                            range: NSRange(location: start, length: output.length - start))
    }

    /// 解析行内标记（`**加粗**`、`` `行内代码` ``）并追加到输出。
    /// - Parameters:
    ///   - text: 行内容
    ///   - baseFont: 基础字体（加粗/代码在其上派生）
    ///   - output: 输出
    private static func appendInline(_ text: String, baseFont: NSFont, to output: NSMutableAttributedString) {
        var index = text.startIndex
        var plain = ""
        func flushPlain() {
            guard !plain.isEmpty else {
                return
            }
            output.append(NSAttributedString(string: plain, attributes: [
                .font: baseFont, .foregroundColor: NSColor.labelColor
            ]))
            plain = ""
        }
        while index < text.endIndex {
            let rest = text[index...]
            if rest.hasPrefix("**"), let close = rest.dropFirst(2).range(of: "**") {
                flushPlain()
                let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                output.append(NSAttributedString(string: String(rest.dropFirst(2)[..<close.lowerBound]),
                                                 attributes: [.font: bold, .foregroundColor: NSColor.labelColor]))
                index = close.upperBound
            } else if rest.hasPrefix("`"), let close = rest.dropFirst(1).range(of: "`") {
                flushPlain()
                let mono = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                output.append(NSAttributedString(string: String(rest.dropFirst(1)[..<close.lowerBound]),
                                                 attributes: [.font: mono, .foregroundColor: NSColor.labelColor]))
                index = close.upperBound
            } else {
                plain.append(text[index])
                index = text.index(after: index)
            }
        }
        flushPlain()
    }
}
