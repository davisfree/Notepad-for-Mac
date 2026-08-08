//
//  NPEditorController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 编辑器控制器：协调 `NPEditorView` 与 `NPTextDocument`。
///
/// 订阅编辑器回调同步文档内容与脏状态；驱动 `NPFindController` / `NPReplaceController`
/// 执行查找替换（匹配计算放到后台线程，结果回主线程更新高亮）。
@MainActor
final class NPEditorController: NPEditorDelegate {

    // MARK: - 属性

    /// 受协调的编辑器视图
    let editorView: NPEditorView
    /// 关联文档（弱引用，文档持有窗口与控制器）
    weak var document: NPTextDocument?

    /// 替换逻辑控制器
    private let replaceController = NPReplaceController()

    /// 光标变化回调（行列，供状态栏等 UI 消费；闭包注入避免 Editor 层依赖 UI 层）
    var onCursorDidChange: ((Int, Int) -> Void)?
    /// 缩放变化回调（供状态栏等 UI 消费）
    var onZoomDidChange: ((Double) -> Void)?
    /// 匹配结果变化回调（current 从 1 开始；total 为 0 表示"未找到"；nil 表示无有效查找，供查找栏统计）
    var onMatchesDidChange: (((current: Int, total: Int)?) -> Void)?
    /// 光标位置变化回调（UTF-16 偏移，供会话备份记录光标）
    var onCursorPositionChange: ((Int) -> Void)?
    /// 文本内容变化回调（用户编辑与"全部替换"后触发，供状态栏字符数等 UI 消费）
    var onTextDidChange: (() -> Void)?
    /// 最近一次查找的搜索词（替换操作时复用）
    private var lastQuery: String?
    /// 最近一次查找的选项（替换操作时复用）
    private var lastOptions: NPFindOptions = []
    /// 当前匹配结果（基于当前 `editorView.text`）
    private var matches: [NSRange] = []
    /// 当前匹配项索引
    private var currentMatchIndex: Int?

    // MARK: - 初始化

    /// 以编辑器视图与文档创建控制器，并接管编辑器委托、装入文档内容。
    /// - Parameters:
    ///   - editorView: 编辑器视图
    ///   - document: 关联文档
    init(editorView: NPEditorView, document: NPTextDocument) {
        self.editorView = editorView
        self.document = document
        editorView.delegate = self
        editorView.text = document.textContent
    }

    // MARK: - 查找

    /// 执行查找（后台计算，完成后在主线程更新视图高亮并选中首个匹配）。
    /// - Parameters:
    ///   - query: 搜索词
    ///   - options: 查找选项
    func performFind(query: String, options: NPFindOptions) async {
        lastQuery = query
        lastOptions = options
        let text = editorView.text
        do {
            let found = try await Task.detached(priority: .userInitiated) {
                try NPFindController().allMatches(in: text, query: query, options: options)
            }.value
            matches = found
            applyMatchHighlight(currentIndex: found.isEmpty ? nil : 0)
        } catch {
            // 非法正则 / 空查询：清除高亮，错误展示由查找栏 UI 负责（04 §3.3）
            matches = []
            currentMatchIndex = nil
            editorView.highlightMatches([], currentIndex: -1)
            onMatchesDidChange?(nil)
        }
    }

    // MARK: - 查找导航

    /// 定位下一个匹配（回绕；无新查找词时沿用上次查找词，对齐 Win11 ⌘G 行为）。
    func findNextMatch() async {
        await stepMatch(by: 1)
    }

    /// 定位上一个匹配（回绕；无新查找词时沿用上次查找词，对齐 Win11 ⇧⌘G 行为）。
    func findPreviousMatch() async {
        await stepMatch(by: -1)
    }

    /// 以步进定位匹配（文本可能已变化，先重新计算匹配范围）。
    /// - Parameter delta: 步进（+1 下一个 / -1 上一个）
    private func stepMatch(by delta: Int) async {
        guard let query = lastQuery, !query.isEmpty else {
            return
        }
        let options = lastOptions
        let text = editorView.text
        do {
            matches = try await Task.detached(priority: .userInitiated) {
                try NPFindController().allMatches(in: text, query: query, options: options)
            }.value
        } catch {
            matches = []
        }
        guard !matches.isEmpty else {
            currentMatchIndex = nil
            applyMatchHighlight(currentIndex: nil)
            return
        }
        let base = currentMatchIndex ?? (delta > 0 ? -1 : 0)
        let next = (base + delta + matches.count) % matches.count
        applyMatchHighlight(currentIndex: next)
    }

    // MARK: - 替换

    /// 替换当前匹配项，并以前次查询条件重新查找刷新高亮。
    /// - Parameter replacement: 替换内容
    func replaceCurrentMatch(with replacement: String) {
        guard let index = currentMatchIndex, matches.indices.contains(index), let query = lastQuery else {
            return
        }
        editorView.text = replaceController.replacing(matches[index], in: editorView.text, with: replacement)
        syncDocument()
        Task {
            await performFind(query: query, options: lastOptions)
        }
    }

    /// 替换全部匹配，返回替换次数。
    /// - Parameter replacement: 替换内容
    /// - Returns: 实际替换次数
    @discardableResult
    func replaceAll(with replacement: String) async -> Int {
        guard let query = lastQuery else {
            return 0
        }
        let options = lastOptions
        let text = editorView.text
        let found: [NSRange]
        do {
            found = try await Task.detached(priority: .userInitiated) {
                try NPFindController().allMatches(in: text, query: query, options: options)
            }.value
        } catch {
            return 0
        }
        guard !found.isEmpty else {
            return 0
        }
        let (newText, count) = replaceController.replacingAll(matches: found, in: text, with: replacement)
        editorView.text = newText
        matches = []
        currentMatchIndex = nil
        editorView.highlightMatches([], currentIndex: -1)
        onMatchesDidChange?(nil)
        syncDocument()
        return count
    }

    // MARK: - 匹配高亮

    /// 应用匹配高亮并选中当前匹配（不抢占查找栏焦点），同时回传统计。
    /// - Parameter currentIndex: 当前匹配索引（nil 表示无当前匹配）
    private func applyMatchHighlight(currentIndex: Int?) {
        currentMatchIndex = currentIndex
        editorView.highlightMatches(matches, currentIndex: currentIndex ?? -1)
        if let currentIndex, matches.indices.contains(currentIndex) {
            // 用 selectedRange 而非 selectRange：查找输入时不把焦点抢回编辑区
            editorView.selectedRange = matches[currentIndex]
            onMatchesDidChange?((current: currentIndex + 1, total: matches.count))
        } else {
            onMatchesDidChange?((current: 0, total: matches.count))
        }
    }

    // MARK: - NPEditorDelegate

    /// 编辑内容变更：回写文档 `textContent` 并标记脏状态。
    /// - Parameter editor: 编辑器视图
    func editorDidChangeContent(_ editor: NPEditorView) {
        syncDocument()
    }

    /// 选区变更：转发行列给订阅方（状态栏等），并回报光标 UTF-16 偏移（会话备份）。
    /// - Parameter editor: 编辑器视图
    func editorDidChangeSelection(_ editor: NPEditorView) {
        onCursorDidChange?(editor.currentLine, editor.currentColumn)
        onCursorPositionChange?(editor.selectedRange.location)
    }

    /// 缩放变更：转发给订阅方（状态栏等）。
    /// - Parameters:
    ///   - editor: 编辑器视图
    ///   - zoomLevel: 新缩放比例
    func editorDidChangeZoomLevel(_ editor: NPEditorView, zoomLevel: Double) {
        onZoomDidChange?(zoomLevel)
    }

    // MARK: - 私有

    /// 将编辑器内容同步到文档并标记脏状态。
    /// 统一在文本变化（用户编辑 `editorDidChangeContent`、全部替换 `replaceAll`）后调用，
    /// 故 `onTextDidChange` 在此触发可覆盖两条路径。
    private func syncDocument() {
        guard let document else {
            return
        }
        document.textContent = editorView.text
        document.updateChangeCount(.changeDone)
        onTextDidChange?()
    }
}
