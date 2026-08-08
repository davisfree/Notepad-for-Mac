//
//  NPConstants.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 全局常量。
enum NPConstants {

    // MARK: - 主菜单项 tag

    /// 主菜单项 tag（用于 `validateMenuItem` 识别与勾选状态管理）。
    enum MenuTag {
        /// 格式 → 自动换行
        static let wordWrap = 100
        /// 视图 → 状态栏
        static let statusBar = 200
        /// 视图 → 主题 → 浅色模式
        static let themeLight = 310
        /// 视图 → 主题 → 深色模式
        static let themeDark = 311
        /// 视图 → 主题 → 跟随系统
        static let themeSystem = 312
        /// 视图 → 始终在最前
        static let alwaysOnTop = 400
        /// 文件 → 打开最近使用的（子菜单容器）
        static let recentDocuments = 500
        /// Notepad → 服务（子菜单容器）
        static let services = 600
        /// Notepad → 显示语言 → 跟随系统
        static let languageSystem = 710
        /// Notepad → 显示语言 → English
        static let languageEnglish = 711
        /// Notepad → 显示语言 → 简体中文
        static let languageZhHans = 712
        /// Notepad → 显示语言 → 繁體中文
        static let languageZhHant = 713
    }

    // MARK: - 菜单标识

    /// "打开最近使用的"子菜单 identifier（`NSMenuDelegate` 动态重建时识别用）
    static let recentDocumentsMenuIdentifier = "RecentDocumentsMenu"

    // MARK: - 编辑器

    /// 缩放步进（10%，对齐 Win11 Notepad ⌘+/⌘- 行为）
    static let zoomStep = 0.1

    // MARK: - 大文件

    /// 大文件只读阈值（10MB；超过时提示并以只读模式打开，PRD FR-001、01 §3.3）
    static let largeFileThreshold = 10 * 1024 * 1024

    // MARK: - 反馈

    /// 反馈收件邮箱（帮助 → 发送反馈…，06_RELEASE §7.2；发布前替换为真实地址）。
    /// 占位地址使用保留域 `.example`，避免误发到真实域名。
    static let feedbackEmail = "feedback@notepadmac.example"

    // MARK: - 纯文本文件类型（v1.4 退役）
    ///
    /// 运行时不再用于过滤——`NPDocumentController` 接受任意类型，编码检测在
    /// `read(from:)` 中判定。本清单保留作文档参考（常见纯文本扩展名/UTI）。

    /// 受支持的纯文本类型清单（文档参考，不在运行时用于过滤）。
    enum TextTypes {
        /// 显式受支持的 UTI（部分系统类型 `UTType` 判定可能不命中，如 `com.microsoft.batch`）
        static let utiSet: Set<String> = [
            "public.plain-text",
            "public.utf8-plain-text",
            "public.utf16-plain-text",
            "public.utf16-external-plain-text",
            "public.log",
            "public.shell-script",
            "public.python-script",
            "public.javascript",
            "public.json",
            "public.xml",
            "public.html",
            "public.css",
            "public.script",
            "com.microsoft.batch",
        ]

        /// 常见纯文本扩展名（系统可能将未知扩展名判定为 `public.data`，须按扩展名兜底）
        static let extensionSet: Set<String> = [
            "txt", "text", "log",
            "bat", "cmd", "sh", "bash", "zsh", "py",
            "js", "mjs", "cjs", "ts", "json",
            "xml", "html", "htm", "css",
            "md", "markdown",
            "ini", "cfg", "conf", "env",
            "csv", "tsv", "yml", "yaml",
            "gitignore", "editorconfig",
        ]

        /// 打开面板过滤用的完整类型列表（UTI + 扩展名混合，`NSOpenPanel.allowedFileTypes` 两者皆可）
        static let allTypes: [String] = Array(utiSet.union(extensionSet)).sorted()
    }
}
