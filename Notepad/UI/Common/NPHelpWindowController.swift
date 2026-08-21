//
//  NPHelpWindowController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-21.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 帮助窗口控制器（帮助 → 查看帮助，PRD 4.1）。
///
/// 以只读文本视图渲染 `NPHelpContent` 加载的本地化 Markdown 帮助正文
/// （经 `NPMarkdownRenderer` 转为真实字体属性——`AttributedString(markdown:)`
/// 的 `presentationIntent` 语义属性不会被 AppKit `NSTextView` 解析）。
/// 窗口由 `AppDelegate` 懒创建并持有，关闭仅隐藏（`isReleasedWhenClosed = false`）。
@MainActor
final class NPHelpWindowController: NSWindowController {

    // MARK: - 初始化

    /// 创建帮助窗口。
    /// - Parameter markdown: 帮助正文（默认取自主 Bundle 的本地化 Help.md；nil 时显示占位文案，测试可注入）
    init(markdown: String? = NPHelpContent.loadMarkdown()) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 360)
        super.init(window: window)
        window.title = NSLocalizedString("Help.Window.Title", comment: "帮助窗口标题")
        assembleContent(markdown: markdown)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("本工程不使用 nib/storyboard（纯代码布局）")
    }

    // MARK: - 私有

    /// 帮助正文字号
    private static let bodyFontSize: CGFloat = 13

    /// 装配窗口内容：滚动视图 + 只读文本视图。
    /// - Parameter markdown: 帮助正文（nil 时显示"帮助内容不可用"占位）
    private func assembleContent(markdown: String?) {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        // 宽度跟随滚动视图，纵向自由滚动
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.textStorage?.setAttributedString(Self.render(markdown: markdown))
        scrollView.documentView = textView
        window?.contentView = scrollView
    }

    /// 渲染帮助正文为属性字符串（Markdown 标题/加粗/列表/行内代码生效）。
    /// - Parameter markdown: 帮助正文（nil 时返回占位文案）
    /// - Returns: 属性字符串
    private static func render(markdown: String?) -> NSAttributedString {
        guard let markdown else {
            return NSAttributedString(
                string: NSLocalizedString("Help.Unavailable", comment: "帮助内容缺失时的占位文案"),
                attributes: [
                    .font: NSFont.systemFont(ofSize: bodyFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
        }
        return NPMarkdownRenderer.render(markdown: markdown)
    }
}
