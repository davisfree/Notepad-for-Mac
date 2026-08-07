//
//  NPFindBarController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 查找栏控制器（UI 层组合根，非契约类型）。
///
/// 实现 `NPFindBarDelegate`：把查找栏交互转译为 `NPEditorController` 调用；
/// 负责查找栏在窗口内容视图顶部的显隐（作为垂直 NSStackView 首个成员，显示时把编辑区
/// 向下推动、不遮挡内容，02 §5.2）。
/// FindBar 与 Editor 两个同层模块之间仅经委托协议与闭包通信（08 §3）。
@MainActor
final class NPFindBarController: NPFindBarDelegate {

    // MARK: - 属性

    /// 查找栏视图
    let findBar: NPFindBarView

    /// 编辑器控制器（弱引用）
    private weak var editorController: NPEditorController?
    /// 编辑器视图（弱引用）
    private weak var editorView: NPEditorView?

    /// 高度约束（替换模式展开/收起时更新）
    private var heightConstraint: NSLayoutConstraint?
    /// 是否已挂载（显示中）
    private var isMounted = false

    // MARK: - 初始化

    /// 创建控制器并接线：查找栏委托、匹配结果回流、显隐请求回调。
    /// - Parameters:
    ///   - editorController: 编辑器控制器
    ///   - editorView: 编辑器视图
    init(editorController: NPEditorController, editorView: NPEditorView) {
        self.findBar = NPFindBarView(frame: .zero)
        self.editorController = editorController
        self.editorView = editorView
        findBar.delegate = self
        let heightConstraint = findBar.heightAnchor.constraint(equalToConstant: NPFindBarView.singleLineHeight)
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
        findBar.onHeightChange = { [weak self] height in
            self?.heightConstraint?.constant = height
        }
        editorController.onMatchesDidChange = { [weak self] result in
            self?.findBar.matchResult = result.map { result in
                NPMatchResult(currentIndex: result.current, totalCount: result.total)
            }
        }
        editorView.onFindBarVisibilityChange = { [weak self] visible, replaceMode in
            self?.setMounted(visible, replaceMode: replaceMode)
        }
    }

    // MARK: - 挂载

    /// 显示/隐藏查找栏（编辑区上方推动布局；NSStackView 自动折叠隐藏成员）。
    /// - Parameters:
    ///   - mounted: 是否显示
    ///   - replaceMode: 是否展开替换区域
    private func setMounted(_ mounted: Bool, replaceMode: Bool) {
        guard mounted != isMounted else {
            findBar.isReplaceMode = replaceMode
            return
        }
        isMounted = mounted
        if mounted {
            // TODO: 02 §5.2 滑入动画（0.2s ease-out），当前直接显隐
            heightConstraint?.constant = replaceMode ? NPFindBarView.expandedHeight
                                                     : NPFindBarView.singleLineHeight
            findBar.isHidden = false
            findBar.isReplaceMode = replaceMode
            findBar.focusFindField()
            findBar.selectFindText()
        } else {
            findBar.isHidden = true
        }
    }

    // MARK: - NPFindBarDelegate

    /// 查找文本变化：实时查找高亮。
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - text: 当前查找文本
    func findBar(_ findBar: NPFindBarView, didChangeFindText text: String) {
        let options = findBar.options
        Task {
            await editorController?.performFind(query: text, options: options)
        }
    }

    /// 替换文本变化（替换动作发生时再读取，此处无需处理）。
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - text: 当前替换文本
    func findBar(_ findBar: NPFindBarView, didChangeReplaceText text: String) {
        // 替换文本在执行替换时经 findBar.replaceText 读取
    }

    /// 查找下一个。
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestFindNext(_ findBar: NPFindBarView) {
        Task {
            await editorController?.findNextMatch()
        }
    }

    /// 查找上一个。
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestFindPrevious(_ findBar: NPFindBarView) {
        Task {
            await editorController?.findPreviousMatch()
        }
    }

    /// 替换当前匹配。
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestReplace(_ findBar: NPFindBarView) {
        editorController?.replaceCurrentMatch(with: findBar.replaceText)
    }

    /// 全部替换。
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestReplaceAll(_ findBar: NPFindBarView) {
        Task {
            await editorController?.replaceAll(with: findBar.replaceText)
        }
    }

    /// 查找选项变化：以新选项重新查找。
    /// - Parameters:
    ///   - findBar: 查找栏视图
    ///   - options: 新选项
    func findBarDidChangeOptions(_ findBar: NPFindBarView, options: NPFindOptions) {
        let query = findBar.findText
        guard !query.isEmpty else {
            return
        }
        Task {
            await editorController?.performFind(query: query, options: options)
        }
    }

    /// 关闭查找栏（经编辑器统一入口，清除高亮并回流显隐状态）。
    /// - Parameter findBar: 查找栏视图
    func findBarDidRequestClose(_ findBar: NPFindBarView) {
        editorView?.hideFindBar()
    }
}
