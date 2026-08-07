//
//  NPGoToLineController.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// "转到行"对话框控制器（PRD：编辑 → 转到… ⌃G；点击状态栏 Ln/Col 同样触发）。
@MainActor
final class NPGoToLineController {

    // MARK: - 属性

    /// 当前展示中的面板（同一时间至多一个）
    private var activePanel: NPGoToLinePanel?

    /// 当前行号提供者（预填并自动选中，02 §5.5；由调用方注入，默认第 1 行）
    var currentLineProvider: (() -> Int)?

    // MARK: - 初始化

    init() {}

    // MARK: - 展示

    /// 以非模态浮动面板（NSPanel）弹出"转到行"对话框。
    ///
    /// 对齐 Win11 原版交互：独立小对话框，不阻塞编辑区焦点切换；
    /// 面板作为子窗口随宿主窗口联动关闭，不使用模态 sheet（与 `02_UI_DESIGN.md` 一致）。
    /// - Parameters:
    ///   - window: 宿主窗口
    ///   - maxLine: 当前文档最大行号（用于输入校验）
    ///   - completion: 用户确认后回传目标行号；取消时回传 `nil`
    func present(in window: NSWindow, maxLine: Int, completion: @escaping (Int?) -> Void) {
        // 已有面板时聚焦复用，不重复弹出
        if let activePanel {
            activePanel.makeKeyAndOrderFront(nil)
            activePanel.focusInput()
            return
        }
        let currentLine = currentLineProvider?() ?? 1
        let panel = NPGoToLinePanel(maxLine: maxLine, currentLine: currentLine)
        panel.onConfirm = { [weak self, weak panel] lineNumber in
            self?.dismiss(panel)
            completion(lineNumber)
        }
        panel.onCancel = { [weak self, weak panel] in
            self?.dismiss(panel)
            completion(nil)
        }
        window.addChildWindow(panel, ordered: .above)
        // 居中于宿主窗口
        let parentFrame = window.frame
        panel.setFrameOrigin(NSPoint(
            x: parentFrame.midX - panel.frame.width / 2.0,
            y: parentFrame.midY - panel.frame.height / 2.0
        ))
        panel.makeKeyAndOrderFront(nil)
        panel.focusInput()
        activePanel = panel
    }

    // MARK: - 行号校验（纯函数，可无 UI 测试）

    /// 解析并校验行号输入：非数字返回 `nil`；数字越界夹取到 `1...maxLine`。
    /// - Parameters:
    ///   - input: 用户输入
    ///   - maxLine: 最大行号
    /// - Returns: 合法行号（从 1 开始）
    static func clampedLineNumber(_ input: String, maxLine: Int) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed) else {
            return nil
        }
        return min(max(value, 1), max(1, maxLine))
    }

    // MARK: - 私有

    /// 关闭面板并解除子窗口挂载。
    /// - Parameter panel: 面板
    private func dismiss(_ panel: NPGoToLinePanel?) {
        guard let panel else {
            return
        }
        panel.parent?.removeChildWindow(panel)
        panel.close()
        if activePanel === panel {
            activePanel = nil
        }
    }
}
