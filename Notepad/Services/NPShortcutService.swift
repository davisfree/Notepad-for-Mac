//
//  NPShortcutService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit
#if canImport(AppIntents)
import AppIntents
#endif

/// 快捷指令（Shortcuts App）集成服务（PRD FR-024，04 §5.4）。
///
/// 方案选择：**App Intents + `if #available(macOS 13, *)` 优雅降级**。
/// App Shortcuts 是现代 Shortcuts 集成（免注册即出现在快捷指令 App），
/// `NSUserActivity` 方案仅覆盖 Siri 建议且属遗留路径；macOS 12 上 `registerShortcuts`
/// 为空操作（不注册、不崩溃），Intents 类型整体以 `@available(macOS 13, *)` 标注。
/// 动作执行经闭包注入路由（打开文件 / 新建文档），避免 Services 层逆向依赖 UI 层（08 §3）。
@MainActor
final class NPShortcutService {

    // MARK: - 单例

    static let shared = NPShortcutService()

    // MARK: - 动作路由（App 层注入）

    /// "用 Notepad 打开文件"执行路由
    var openFileHandler: ((URL) -> Void)?
    /// "创建新文本文件"执行路由
    var createDocumentHandler: (() -> Void)?

    // MARK: - 初始化

    private init() {}

    // MARK: - 注册

    /// 注册 App Shortcuts：用 Notepad 打开文件、创建新文本文件。
    /// macOS 13+ 生效；macOS 12 为空操作（08 §1.2 约束 2）。
    func registerShortcuts() {
        #if canImport(AppIntents)
        if #available(macOS 13, *) {
            NPAppShortcuts.updateAppShortcutParameters()
        }
        // macOS 12：App Intents 不可用，不注册不崩溃（FR-024 降级）
        #endif
    }
}

#if canImport(AppIntents)

/// "用 Notepad 打开文件"快捷指令动作（FR-024）。
@available(macOS 13, *)
struct NPOpenFileIntent: AppIntent {
    /// 动作标题
    static var title: LocalizedStringResource = "Open File with Notepad"
    /// 动作描述
    static var description = IntentDescription("Opens a text file in Notepad.")

    /// 目标文件
    @Parameter(title: "File")
    var file: IntentFile

    /// 执行：经注入路由打开文件。
    /// - Returns: 结果
    @MainActor
    func perform() async throws -> some IntentResult {
        if let url = file.fileURL {
            NPShortcutService.shared.openFileHandler?(url)
        }
        return .result()
    }
}

/// "创建新文本文件"快捷指令动作（FR-024）。
@available(macOS 13, *)
struct NPCreateTextFileIntent: AppIntent {
    /// 动作标题
    static var title: LocalizedStringResource = "Create New Text File"
    /// 动作描述
    static var description = IntentDescription("Creates a new untitled text document in Notepad.")

    /// 执行：经注入路由新建无标题文档。
    /// - Returns: 结果
    @MainActor
    func perform() async throws -> some IntentResult {
        NPShortcutService.shared.createDocumentHandler?()
        return .result()
    }
}

/// App Shortcuts 清单（macOS 13+ 自动出现在快捷指令 App）。
@available(macOS 13, *)
struct NPAppShortcuts: AppShortcutsProvider {
    /// 快捷指令列表
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NPOpenFileIntent(),
            phrases: [
                "Open file with \(.applicationName)",
                "用 \(.applicationName) 打开文件",
            ],
            shortTitle: "Open File",
            systemImageName: "doc.text"
        )
        AppShortcut(
            intent: NPCreateTextFileIntent(),
            phrases: [
                "Create text file with \(.applicationName)",
                "用 \(.applicationName) 创建新文本文件",
            ],
            shortTitle: "New Text File",
            systemImageName: "doc.badge.plus"
        )
    }
}

#endif
