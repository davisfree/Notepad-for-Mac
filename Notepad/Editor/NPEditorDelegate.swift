//
//  NPEditorDelegate.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 编辑器视图委托协议（所有回调均在主线程触发）。
@MainActor
protocol NPEditorDelegate: AnyObject {
    /// 编辑内容发生变化（用户输入、粘贴、替换等）。
    /// - Parameter editor: 编辑器视图
    func editorDidChangeContent(_ editor: NPEditorView)

    /// 选区或光标位置发生变化。
    /// - Parameter editor: 编辑器视图
    func editorDidChangeSelection(_ editor: NPEditorView)

    /// 缩放比例发生变化。
    /// - Parameters:
    ///   - editor: 编辑器视图
    ///   - zoomLevel: 新缩放比例（1.0 = 100%）
    func editorDidChangeZoomLevel(_ editor: NPEditorView, zoomLevel: Double)
}
