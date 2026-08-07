//
//  NPGoToLinePanel.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// "转到行"浮动面板（02 §5.5：280 × 120，非模态，Enter 确认 / Esc 取消）。
@MainActor
final class NPGoToLinePanel: NSPanel {

    // MARK: - 常量

    /// 面板尺寸（02 §5.5）
    private static let panelSize = NSSize(width: 280, height: 120)

    // MARK: - 回调

    /// 确认回调（回传校验并夹取后的行号）
    var onConfirm: ((Int) -> Void)?
    /// 取消回调（Esc / 取消按钮 / 关闭按钮）
    var onCancel: (() -> Void)?

    // MARK: - 属性

    /// 最大行号（输入校验上限）
    private let maxLine: Int
    /// 行号输入框
    private let inputField = NSTextField()
    /// 是否已回调（防止确认/取消重复触发）
    private var didFinish = false

    // MARK: - 初始化

    /// 创建面板。
    /// - Parameters:
    ///   - maxLine: 最大行号（输入校验上限）
    ///   - currentLine: 当前行号（预填并自动选中）
    init(maxLine: Int, currentLine: Int) {
        self.maxLine = max(1, maxLine)
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = NSLocalizedString("GoToLine.Title", comment: "转到行：标题")
        isFloatingPanel = true
        delegate = self
        setupContent(currentLine: currentLine)
    }

    /// 不支持归档恢复。
    /// - Parameter coder: 解码器
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NPGoToLinePanel 不支持 coder 初始化，请使用 init(maxLine:currentLine:)")
    }

    /// 装配标签、输入框与按钮。
    /// - Parameter currentLine: 预填的当前行号
    private func setupContent(currentLine: Int) {
        guard let contentView else {
            return
        }
        let label = NSTextField(labelWithString: NSLocalizedString("GoToLine.LineNumber", comment: "转到行：行号标签"))
        label.frame = NSRect(x: 20, y: 62, width: 60, height: 22)
        contentView.addSubview(label)

        // 仅允许数字（02 §5.5）；非法值在确认时再次校验
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: 1)
        inputField.frame = NSRect(x: 84, y: 60, width: 176, height: 24)
        inputField.formatter = formatter
        inputField.stringValue = "\(max(1, min(currentLine, maxLine)))"
        inputField.target = self
        inputField.action = #selector(handleConfirm(_:))
        contentView.addSubview(inputField)

        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "转到行：取消"),
                                    target: self, action: #selector(handleCancel(_:)))
        cancelButton.frame = NSRect(x: 102, y: 14, width: 82, height: 28)
        cancelButton.keyEquivalent = "\u{1B}" // Esc
        contentView.addSubview(cancelButton)

        let confirmButton = NSButton(title: NSLocalizedString("GoToLine.Go", comment: "转到行：确认"),
                                     target: self, action: #selector(handleConfirm(_:)))
        confirmButton.frame = NSRect(x: 190, y: 14, width: 82, height: 28)
        confirmButton.keyEquivalent = "\r" // Enter
        contentView.addSubview(confirmButton)
    }

    // MARK: - 方法

    /// 聚焦输入框并选中预填行号（02 §5.5）。
    func focusInput() {
        makeFirstResponder(inputField)
        inputField.selectText(nil)
    }

    // MARK: - 动作

    /// 确认：校验行号（越界夹取），非法输入提示后停留。
    /// - Parameter sender: 按钮 / 输入框
    @objc private func handleConfirm(_ sender: Any?) {
        guard let lineNumber = NPGoToLineController.clampedLineNumber(inputField.stringValue, maxLine: maxLine) else {
            NSSound.beep()
            focusInput()
            return
        }
        finish {
            onConfirm?(lineNumber)
        }
    }

    /// 取消。
    /// - Parameter sender: 按钮
    @objc private func handleCancel(_ sender: Any?) {
        finish {
            onCancel?()
        }
    }

    /// 单次回调后结束（关闭由控制器执行）。
    /// - Parameter callback: 回调
    private func finish(_ callback: () -> Void) {
        guard !didFinish else {
            return
        }
        didFinish = true
        callback()
    }
}

// MARK: - NSWindowDelegate

extension NPGoToLinePanel: NSWindowDelegate {
    /// 用户点关闭按钮：视同取消。
    /// - Parameter notification: 关闭通知
    func windowWillClose(_ notification: Notification) {
        finish {
            onCancel?()
        }
    }
}
