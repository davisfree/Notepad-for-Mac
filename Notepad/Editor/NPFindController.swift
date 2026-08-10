//
//  NPFindController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 查找选项。
struct NPFindOptions: OptionSet {
    let rawValue: Int

    /// 区分大小写。**默认不设置（不区分大小写）**，与 Win11 Notepad 行为一致（PRD FR-004）
    static let caseSensitive = NPFindOptions(rawValue: 1 << 0)
    /// 到达文档末尾后从头继续
    static let wrapAround = NPFindOptions(rawValue: 1 << 1)
    /// 正则表达式（增值功能，Win11 原版无）
    static let regularExpression = NPFindOptions(rawValue: 1 << 2)
}

/// 查找相关错误。
enum NPFindError: Error {
    /// 正则表达式非法
    case invalidRegex
    /// 搜索词为空
    case emptyQuery
}

/// 查找逻辑控制器（无 UI 依赖，可在后台线程执行）。
final class NPFindController {

    // MARK: - 初始化

    init() {}

    // MARK: - 查找

    /// 在文本中查找全部匹配。
    /// - Parameters:
    ///   - text: 待搜索文本
    ///   - query: 搜索词
    ///   - options: 查找选项
    /// - Returns: 全部匹配范围（按出现顺序，UTF-16 偏移）
    /// - Throws: `NPFindError.invalidRegex`（正则表达式非法时）、`NPFindError.emptyQuery`（搜索词为空时）
    func allMatches(in text: String, query: String, options: NPFindOptions) throws -> [NSRange] {
        guard !query.isEmpty else {
            throw NPFindError.emptyQuery
        }
        if options.contains(.regularExpression) {
            return try regexMatches(in: text, query: query, options: options)
        }
        return literalMatches(in: text, query: query, options: options)
    }

    /// 从指定位置起查找下一个匹配（支持 `wrapAround`）。
    /// - Parameters:
    ///   - text: 待搜索文本
    ///   - query: 搜索词
    ///   - options: 查找选项
    ///   - location: 起始 UTF-16 偏移（命中范围 location ≥ 该值）
    /// - Returns: 下一个匹配范围；无匹配（或未开启回绕）时返回 `nil`
    /// - Throws: `NPFindError.invalidRegex`、`NPFindError.emptyQuery`
    func nextMatch(in text: String, query: String, options: NPFindOptions, after location: Int) throws -> NSRange? {
        let matches = try allMatches(in: text, query: query, options: options)
        if let next = matches.first(where: { range in range.location >= location }) {
            return next
        }
        if options.contains(.wrapAround) {
            return matches.first
        }
        return nil
    }

    // MARK: - 私有实现

    /// 字面量匹配（默认不区分大小写，对齐 Win11 默认行为）。
    /// - Parameters:
    ///   - text: 待搜索文本
    ///   - query: 搜索词
    ///   - options: 查找选项
    /// - Returns: 全部匹配范围（不重叠，按出现顺序）
    private func literalMatches(in text: String, query: String, options: NPFindOptions) -> [NSRange] {
        let compareOptions: String.CompareOptions = options.contains(.caseSensitive) ? [] : [.caseInsensitive]
        var ranges: [NSRange] = []
        var searchStart = text.startIndex
        while let found = text.range(of: query, options: compareOptions, range: searchStart ..< text.endIndex) {
            ranges.append(NSRange(found, in: text))
            searchStart = found.upperBound
        }
        return ranges
    }

    /// 正则表达式匹配（`NSRegularExpression`）。
    /// - Parameters:
    ///   - text: 待搜索文本
    ///   - query: 正则表达式
    ///   - options: 查找选项
    /// - Returns: 全部匹配范围
    /// - Throws: `NPFindError.invalidRegex`（正则表达式非法时）
    private func regexMatches(in text: String, query: String, options: NPFindOptions) throws -> [NSRange] {
        let regexOptions: NSRegularExpression.Options = options.contains(.caseSensitive) ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: query, options: regexOptions) else {
            throw NPFindError.invalidRegex
        }
        let fullRange = NSRange(text.startIndex ..< text.endIndex, in: text)
        return regex.matches(in: text, range: fullRange).map { match in match.range }
    }
}
