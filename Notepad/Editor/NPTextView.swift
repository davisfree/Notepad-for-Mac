//
//  NPTextView.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 编辑器底层文本视图（`NSTextView` 子类）。
///
/// 负责编辑区默认值：SF Mono 12pt 字体（降级链见 `02_UI_DESIGN.md` 3.1）、8pt 内边距、
/// 复刻配色（浅色 `#FFFFFF`/`#000000`，深色 `#1E1E1E`/`#CCCCCC`，选中高亮 `#0078D4`），
/// 并随 `effectiveAppearance` 切换浅/深色。行为扩展（缩放、查找高亮等）由 `NPEditorView` 承担。
final class NPTextView: NSTextView {

    // MARK: - 常量

    /// 默认字号（`02_UI_DESIGN.md` 3.1）
    private static let defaultFontSize: CGFloat = 12.0
    /// 编辑区内边距（`02_UI_DESIGN.md` 4.3，四边 8pt）
    private static let editorInset: CGFloat = 8.0

    // MARK: - 初始化

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        applyEditorDefaults()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyEditorDefaults()
    }

    // MARK: - 默认配置

    /// 应用纯文本编辑器默认配置：字体、内边距、配色、关闭富文本与自动替换。
    private func applyEditorDefaults() {
        isRichText = false
        isEditable = true
        isSelectable = true
        allowsUndo = true
        font = Self.defaultFont()
        textContainerInset = NSSize(width: Self.editorInset, height: Self.editorInset)
        // 关闭对纯文本无意义的自动替换（引号/破折号/拼写纠正）
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        // 允许字体面板（格式 → 字体…）；所选字体与 baseFont 的同步留待偏好模块
        usesFontPanel = true
        applyAppearanceColors()
    }

    /// 编辑区默认字体：SF Mono 12pt，降级 Menlo / 系统等宽字体（`02_UI_DESIGN.md` 3.1）。
    /// - Returns: 默认字体
    static func defaultFont() -> NSFont {
        if let sfMono = NSFont(name: "SF Mono", size: defaultFontSize) {
            return sfMono
        }
        if let menlo = NSFont(name: "Menlo", size: defaultFontSize) {
            return menlo
        }
        return NSFont.userFixedPitchFont(ofSize: defaultFontSize) ?? NSFont.systemFont(ofSize: defaultFontSize)
    }

    // MARK: - 字体

    /// 更新编辑字体（同步 typingAttributes，保证新输入文字使用同一字体）。
    /// - Parameter font: 目标字体
    func setEditorFont(_ font: NSFont) {
        self.font = font
        typingAttributes[.font] = font
    }

    // MARK: - 配色

    /// 应用复刻配色（色值集中定义于 `NPColorPalette`，动态颜色随 effectiveAppearance 自动解析）。
    private func applyAppearanceColors() {
        backgroundColor = NPColorPalette.editorBackground
        textColor = NPColorPalette.editorText
        insertionPointColor = NPColorPalette.editorText
        // 选中高亮固定 Win11 蓝（不使用系统语义色，其默认为灰色，见 02 §2.3 注意）
        selectedTextAttributes = [
            .backgroundColor: NPColorPalette.selectionBackground,
            .foregroundColor: NPColorPalette.selectionText,
        ]
        typingAttributes[.foregroundColor] = NPColorPalette.editorText
        // 纯文本编辑器关闭连字（02 §3.1）
        typingAttributes[.ligature] = NSNumber(value: 0)
    }

    /// 外观（浅/深色）变化时刷新配色（动态颜色本身自动解析，此处同步 typingAttributes）。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    // MARK: - 字体面板

    /// 字体面板选择结果回写偏好（PRD FR-014 字体全局生效）。
    /// - Parameter sender: 字体管理器
    override func changeFont(_ sender: Any?) {
        super.changeFont(sender)
        // 写回偏好后由 NPEditorView 的 preferencesDidChange 观察者同步各窗口 baseFont
        guard let selectedFont = (typingAttributes[.font] as? NSFont) ?? font else {
            return
        }
        NPPreferences.shared.font = selectedFont
    }
}
