//
//  AppDelegate.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

/// 应用生命周期委托。
///
/// 职责（见 `07_PROJECT_STRUCTURE.md` 2.1）：
/// - 应用生命周期管理（启动、退出、激活）
/// - 主菜单安装与动态更新（`NPMenuBuilder` + `validateMenuItem`）
/// - 窗口装配工厂注入（消除 Document → UI 逆向依赖）
/// - 系统服务注册
/// - 崩溃监控初始化
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - 初始化

    override init() {
        super.init()
        // 禁用 AppKit 窗口状态还原：坏/空的持久状态会抑制启动时的自动新建文档
        // （首次点击 Dock 图标无窗口），且会话恢复本就由 NPBackupService 自研（Phase 3，PRD FR-003）
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        // 显示语言覆盖：非"跟随系统"时写 AppleLanguages；跟随系统时移除残留覆盖，
        // 保证界面语言回落为系统语言。必须早于任何本地化解析，故置于 init（main 启动最早期）；
        // 切换后重启生效（AppleLanguages 由 Foundation 缓存）。
        if let languages = NPPreferences.shared.displayLanguage.appleLanguagesValue {
            UserDefaults.standard.set(languages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        // 首个创建的 NSDocumentController 实例会成为 shared controller，
        // 必须早于任何 NSDocumentController.shared 访问（见 NPDocumentController 注释）
        _ = NPDocumentController()
    }

    // MARK: - NSApplicationDelegate

    /// 启动早期注入窗口装配工厂（必须先于任何文档创建），并按偏好应用主题外观。
    /// - Parameter notification: 启动通知
    func applicationWillFinishLaunching(_ notification: Notification) {
        NPTextDocument.windowControllerFactory = { document in
            NPTabWindowManager.shared.acquireWindowController(for: document)
        }
        // 快捷指令动作路由注入（Services 层不经 UI 层类型，08 §3）
        NPShortcutService.shared.openFileHandler = { url in
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
        NPShortcutService.shared.createDocumentHandler = { [weak self] in
            guard let document = try? self?.makeTrackedUntitledDocument() else {
                return
            }
            NPTabWindowManager.shared.addDocumentAsTabOrNewWindow(document)
        }
        // 初始化主题管理器：读取偏好并应用 NSApp 级外观（已开窗口即时跟随）
        _ = NPThemeManager.shared
    }

    /// 安装主菜单，初始化系统服务；有可恢复会话则恢复，否则确定性新建无标题窗口。
    /// - Parameter notification: 启动通知
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = NPMenuBuilder.buildMainMenu()
        let records = NPBackupService.shared.recoverableRecords()
        // 加载完有效备份后清掉目录中其余文件（超期/临时残留/孤儿/损坏）
        let validBackupIDs = Set(records.compactMap { record in
            UUID(uuidString: record.item.backupContentURL.deletingPathExtension().lastPathComponent)
        })
        NPBackupService.shared.pruneInvalidBackupFiles(keeping: validBackupIDs)
        if !records.isEmpty {
            restoreSession(from: records)
        } else {
            openUntitledWindowIfNoDocuments()
        }
        // 崩溃监控（Sentry，04 §5.5）：懒初始化不阻塞启动；未配置 DSN 或未链接 SDK 时为空操作
        NPCrashReporter.shared.start()
        #if !APP_STORE
        // 自动更新（Sparkle，04 §5.2）：初始化即启动更新周期；App Store 构建整体剔除（06 §2.2）
        _ = NPUpdateService.shared
        #endif
        // macOS 服务菜单（PRD FR-021）：注册服务提供者，启用"用所选文字新建文档"服务
        NSApp.servicesProvider = self
        NPShortcutService.shared.registerShortcuts()
    }

    /// 退出行为（01 §3.5）：静默退出（用户规则 2）——内容已在会话备份，备份保留供下次恢复。
    ///
    /// 系统退出流程先于本方法发起未保存文稿复查，故对脏文档的拦截由
    /// `NPDocumentController` 覆写的 `reviewUnsavedDocuments` / `closeAllDocuments`
    /// 在更早阶段完成（先落盘 + 清脏，再走系统复查，此时无脏文档、不弹任何面板）。
    /// 本方法保留同一套落盘 + 清脏作为兜底，并返回 `.terminateNow`。
    /// 未保存状态由磁盘备份承载，下次启动经会话恢复还原并重新标脏。
    /// - Parameter sender: 应用
    /// - Returns: 终止答复
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 标记退出流程：此后若发生窗口关闭（登出/关机路径），关窗仍保留备份供会话恢复
        NPBackupService.shared.markTerminating()
        NPBackupService.shared.flushAllPendingWrites()
        // 退出清理：只保留当前打开标签的备份，删除历史残留（崩溃遗留/旧版本），
        // 保证下次启动恢复的窗口数 = 退出时的窗口数，不随使用累积
        NPBackupService.shared.pruneBackupsForQuit()
        for document in NSDocumentController.shared.documents {
            document.updateChangeCount(.changeCleared)
        }
        return .terminateNow
    }

    /// 文档类应用：关闭最后一个窗口后不退出，保持菜单栏可用。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 启动时是否自动新建无标题文档。
    ///
    /// 固定返回 `false`：macOS 26 下系统持久状态可能抑制该路径（冷启动无任何窗口），
    /// 新建窗口由 `applicationDidFinishLaunching` / `applicationShouldHandleReopen`
    /// 经 `openUntitledWindowIfNoDocuments()` 确定性完成。
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    /// 无窗口时点击 Dock 图标：优先把内存中仍打开的文档（关窗摘除路径保留的）重建为窗口；
    /// 无任何文档时新建无标题窗口。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let documents = NSDocumentController.shared.documents.compactMap { $0 as? NPTextDocument }
            if documents.isEmpty {
                openUntitledWindowIfNoDocuments()
            } else {
                for document in documents {
                    NPTabWindowManager.shared.addDocumentAsTabOrNewWindow(document)
                }
            }
        }
        return true
    }

    // MARK: - 私有

    /// 创建无标题文档并确保其纳入 `NSDocumentController.documents` 跟踪。
    ///
    /// macOS 26 下 `makeUntitledDocument(ofType:)` 不会把文档加入 `documents`
    /// （实测返回后 `documents.count` 仍为 0），不补登记会导致
    /// `documents.isEmpty` 守卫失效而重复创建、最近文件/会话恢复丢失。
    /// - Returns: 无标题文档
    private func makeTrackedUntitledDocument() throws -> NPTextDocument? {
        guard let document = try NSDocumentController.shared.makeUntitledDocument(
            ofType: "public.plain-text") as? NPTextDocument else {
            return nil
        }
        let controller = NSDocumentController.shared
        if !controller.documents.contains(where: { $0 === document }) {
            controller.addDocument(document)
        }
        return document
    }

    /// 无任何文档时新建无标题窗口（启动与 reopen 共用，保证全路径恰好一个窗口）。
    private func openUntitledWindowIfNoDocuments() {
        guard NSDocumentController.shared.documents.isEmpty else {
            return
        }
        do {
            guard let document = try makeTrackedUntitledDocument() else {
                return
            }
            NPTabWindowManager.shared.openInNewWindow(document)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - 会话恢复（PRD FR-003）

    /// 恢复上次会话：按窗口归属分组恢复标签（内容 + 光标）。
    /// - Parameter records: 备份记录（已按组/标签序/时间戳排序）
    private func restoreSession(from records: [NPBackupRecord]) {
        var windowControllersByGroup: [UUID: NPEditorWindowController] = [:]
        for record in records {
            guard let document = restoreDocument(for: record) else {
                continue
            }
            let windowController: NPEditorWindowController
            if let existing = windowControllersByGroup[record.windowGroupID] {
                existing.addTab(for: document)
                windowController = existing
            } else {
                windowController = NPTabWindowManager.shared.openInNewWindow(document)
                windowControllersByGroup[record.windowGroupID] = windowController
            }
            // 沿用既有备份标识（避免恢复后产生重复备份），并恢复光标位置
            if let backupID = UUID(uuidString: record.item.backupContentURL.deletingPathExtension().lastPathComponent) {
                NPBackupService.shared.adoptBackup(backupID, for: document)
            }
            if let entry = windowController.tabBarController.entries.last,
               entry.document === document {
                let length = (document.textContent as NSString).length
                let location = min(max(record.item.cursorPosition, 0), length)
                entry.editorController.editorView.selectedRange = NSRange(location: location, length: 0)
            }
        }
        // 兜底：全部恢复失败时仍保证一个窗口
        openUntitledWindowIfNoDocuments()
    }

    /// 恢复单个文档（三态：未命名 → 备份内容标脏；已存盘有改动 → 备份内容标脏；已存盘无改动 → 原样）。
    /// - Parameter record: 备份记录
    /// - Returns: 恢复的文档（原文件与备份均不可读时为 nil）
    private func restoreDocument(for record: NPBackupRecord) -> NPTextDocument? {
        let backupContent = try? String(contentsOf: record.item.backupContentURL, encoding: .utf8)
        guard let originalFileURL = record.item.originalFileURL else {
            // 未命名文档：恢复备份内容与光标；仅非空内容标脏（空文档与新建无异，不应提示未保存）
            guard let document = try? makeTrackedUntitledDocument(), let backupContent else {
                return nil
            }
            document.textContent = backupContent
            if !backupContent.isEmpty {
                document.updateChangeCount(.changeDone)
            }
            return document
        }
        // 已存盘文档：从原路径打开
        guard let document = try? NPTextDocument(contentsOf: originalFileURL,
                                                 ofType: "public.plain-text") else {
            // 原文件已丢失：退化为未命名文档 + 备份内容；仅非空内容标脏
            guard let fallback = try? makeTrackedUntitledDocument(), let backupContent else {
                return nil
            }
            fallback.textContent = backupContent
            if !backupContent.isEmpty {
                fallback.updateChangeCount(.changeDone)
            }
            return fallback
        }
        let controller = NSDocumentController.shared
        if !controller.documents.contains(where: { $0 === document }) {
            controller.addDocument(document)
        }
        // 备份内容与原文件不同（有未保存更改）→ 用备份内容并标脏
        if let backupContent,
           NPBackupService.shouldRestoreBackupContent(backupContent: backupContent,
                                                      fileContent: document.textContent) {
            document.textContent = backupContent
            document.updateChangeCount(.changeDone)
        }
        return document
    }

    // MARK: - 文件菜单动作

    /// 文件 → 新建窗口（⌘N）：创建无标题文档并强制在新窗口托管。
    /// - Parameter sender: 菜单项
    /// - Note: 不走 `NSDocumentController.newDocument(_:)`——其文档创建可能异步完成，
    ///   临时路由标志会在工厂执行前被还原，导致新文档被误路由为当前窗口的标签。
    @objc func newWindow(_ sender: Any?) {
        do {
            guard let document = try makeTrackedUntitledDocument() else {
                return
            }
            NPTabWindowManager.shared.openInNewWindow(document)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// 文件 → 新建标签页（⌘T）：创建无标题文档但不 showWindows，加入当前窗口标签组。
    /// - Parameter sender: 菜单项
    @objc func newTab(_ sender: Any?) {
        do {
            guard let document = try makeTrackedUntitledDocument() else {
                return
            }
            NPTabWindowManager.shared.addDocumentAsTabOrNewWindow(document)
        } catch {
            // 创建失败：NSDocumentController 已记录错误，无进一步恢复路径
        }
    }

    /// 文件 → 打开…（⌘O）。
    /// - Parameter sender: 菜单项
    @objc func openDocumentAction(_ sender: Any?) {
        NSDocumentController.shared.openDocument(sender)
    }

    /// 打开最近使用的 → 文件项。
    /// - Parameter sender: 菜单项（representedObject 为文件 URL）
    @objc func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else {
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// 文件 → 打开最近使用的 → 清空菜单。
    /// - Parameter sender: 菜单项
    @objc func clearRecentDocuments(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    /// 文件 → 页面设置…（路由到打印服务，作用于当前活动文档）。
    /// - Parameter sender: 菜单项
    @objc func showPageSetupAction(_ sender: Any?) {
        guard let document = currentDocument() else {
            return
        }
        NPPrintService.shared.showPageSetup(for: document, in: NSApp.mainWindow) { _ in }
    }

    /// 文件 → 打印…（⌘P，路由到打印服务，作用于当前活动文档）。
    /// - Parameter sender: 菜单项
    @objc func printDocumentAction(_ sender: Any?) {
        guard let document = currentDocument() else {
            return
        }
        NPPrintService.shared.printDocument(document, in: NSApp.mainWindow) { _ in }
    }

    /// 当前活动文档（标签组架构下取当前窗口选中标签的文档）。
    /// - Returns: 文档（无窗口时为 nil）
    private func currentDocument() -> NPTextDocument? {
        let windowController = NSApp.mainWindow?.windowController as? NPEditorWindowController
        return windowController?.tabBarController.selectedEntry?.document
    }

    // MARK: - 应用菜单动作

    /// 偏好设置窗口控制器（懒创建并持有；窗口关闭仅隐藏，复用同一实例）
    private lazy var preferencesWindowController = NPPreferencesWindowController()

    /// 帮助窗口控制器（懒创建并持有；窗口关闭仅隐藏，复用同一实例）
    private lazy var helpWindowController = NPHelpWindowController()

    /// Notepad → 偏好设置…（⌘,）：显示偏好设置窗口并激活应用。
    /// 首次显示时居中：有主窗口则居中于主窗口之上，否则居中于屏幕。
    /// - Parameter sender: 菜单项
    @objc func showPreferences(_ sender: Any?) {
        let controller = preferencesWindowController
        // 须先于 showWindow 记录可见性：showWindow 之后 isVisible 已为 true
        let isFirstShow = controller.window?.isVisible != true
        controller.showWindow(nil)
        if isFirstShow, let window = controller.window {
            if let mainWindow = NSApp.mainWindow, mainWindow != window {
                // 居中于主窗口（窗口 level 高于普通窗口时 mainWindow 可能是面板，需排除自身）
                let mainFrame = mainWindow.frame
                let size = window.frame.size
                window.setFrameOrigin(NSPoint(
                    x: mainFrame.midX - size.width / 2,
                    y: mainFrame.midY - size.height / 2
                ))
            } else {
                window.center()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

#if !APP_STORE
    /// Notepad → 检查更新…（仅直发/Homebrew 构建；App Store 构建菜单项已按 `#if !APP_STORE` 剔除）。
    /// - Parameter sender: 菜单项
    @objc func checkForUpdates(_ sender: Any?) {
        NPUpdateService.shared.checkForUpdates()
    }
#endif

    /// 帮助 → 查看帮助（应用内帮助窗口，正文取自本地化 Help.md 资源）。
    /// 首次显示时居中于屏幕。
    /// - Parameter sender: 菜单项
    @objc func showHelp(_ sender: Any?) {
        let controller = helpWindowController
        // 须先于 showWindow 记录可见性：showWindow 之后 isVisible 已为 true
        let isFirstShow = controller.window?.isVisible != true
        controller.showWindow(nil)
        if isFirstShow {
            controller.window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 帮助 → 发送反馈…（06_RELEASE §7.2：邮件渠道）。
    /// - Parameter sender: 菜单项
    @objc func sendFeedback(_ sender: Any?) {
        guard let url = NPFeedbackComposer.composeMailURL() else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 格式菜单动作

    /// 格式 → 字体…（打开系统字体面板）。
    /// - Parameter sender: 菜单项
    @objc func showFontPanel(_ sender: Any?) {
        NSFontManager.shared.orderFrontFontPanel(sender)
    }

    // MARK: - 视图菜单动作

    /// 视图 → 状态栏（⌘/，开关写入偏好；显隐由状态栏模块消费，04 §3.1）。
    /// - Parameter sender: 菜单项
    @objc func toggleStatusBar(_ sender: NSMenuItem) {
        NPPreferences.shared.isStatusBarVisible.toggle()
    }

    /// 视图 → 主题 → 浅色模式。
    /// - Parameter sender: 菜单项
    @objc func setThemeLight(_ sender: NSMenuItem) {
        NPThemeManager.shared.apply(theme: .light)
    }

    /// 视图 → 主题 → 深色模式。
    /// - Parameter sender: 菜单项
    @objc func setThemeDark(_ sender: NSMenuItem) {
        NPThemeManager.shared.apply(theme: .dark)
    }

    /// 视图 → 主题 → 跟随系统。
    /// - Parameter sender: 菜单项
    @objc func setThemeSystem(_ sender: NSMenuItem) {
        NPThemeManager.shared.apply(theme: .system)
    }

    /// 视图 → 始终在最前（切换当前窗口浮动层级）。
    /// - Parameter sender: 菜单项
    @objc func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        guard let window = NSApp.mainWindow else {
            return
        }
        window.level = window.level == .floating ? .normal : .floating
    }

    // MARK: - 菜单状态验证

    /// 菜单项状态验证：状态栏/主题勾选读偏好，始终在最前读当前窗口层级，打印项随活动文档启停。
    /// - Parameter menuItem: 待验证菜单项
    /// - Returns: 是否可用
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showPageSetupAction(_:))
            || menuItem.action == #selector(printDocumentAction(_:)) {
            return currentDocument() != nil
        }
        switch menuItem.tag {
        case NPConstants.MenuTag.statusBar:
            menuItem.state = NPPreferences.shared.isStatusBarVisible ? .on : .off
        case NPConstants.MenuTag.themeLight:
            menuItem.state = NPPreferences.shared.theme == .light ? .on : .off
        case NPConstants.MenuTag.themeDark:
            menuItem.state = NPPreferences.shared.theme == .dark ? .on : .off
        case NPConstants.MenuTag.themeSystem:
            menuItem.state = NPPreferences.shared.theme == .system ? .on : .off
        case NPConstants.MenuTag.alwaysOnTop:
            menuItem.state = NSApp.mainWindow?.level == .floating ? .on : .off
        default:
            break
        }
        return true
    }
}

// MARK: - NSMenuDelegate（打开最近使用的动态重建）

extension AppDelegate: NSMenuDelegate {
    /// 菜单展开前重建"打开最近使用的"文件列表。
    /// - Parameter menu: 待更新菜单
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == NPConstants.recentDocumentsMenuIdentifier else {
            return
        }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(openRecentDocument(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let clearItem = NSMenuItem(
            title: NSLocalizedString("Menu.File.ClearRecent", comment: "菜单：清空最近使用"),
            action: #selector(clearRecentDocuments(_:)),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
    }
}

// MARK: - NSServicesMenuRequestor（PRD FR-021：macOS 服务菜单）

extension AppDelegate: NSServicesMenuRequestor {
    /// 服务"用所选文字新建文档"：从服务剪贴板读取所选文字，新建文档并开窗。
    ///
    /// AppKit 服务调用约定在主线程投递（`NSServicesMenuRequestor` 语义），
    /// 编译器无法静态证明跨隔离安全 → `nonisolated` + `MainActor.assumeIsolated` 显式断言。
    /// - Parameter pboard: 服务系统传入的剪贴板（含发送类型的所选数据）
    /// - Returns: 是否成功处理
    nonisolated func readSelection(from pboard: NSPasteboard) -> Bool {
        guard let text = pboard.string(forType: .string) else {
            return false
        }
        return MainActor.assumeIsolated {
            do {
                guard let document = try makeTrackedUntitledDocument() else {
                    return false
                }
                document.textContent = text
                document.updateChangeCount(.changeDone)
                NPTabWindowManager.shared.openInNewWindow(document)
                return true
            } catch {
                return false
            }
        }
    }
}
