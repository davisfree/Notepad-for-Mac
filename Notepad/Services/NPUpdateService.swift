//
//  NPUpdateService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-06.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

#if !APP_STORE
// App Store 构建整体剔除本模块（Apple 禁止应用内自更新，01 §6.3 / 06 §2.2）；
// 编译标志 `APP_STORE` 由 App Store 构建配置注入（见 06_RELEASE.md「构建配置差异」）。

import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// 自动更新服务（Sparkle 封装，04 §5.2）。
///
/// - 生命周期：`shared` 首次访问即初始化 `SPUStandardUpdaterController`（startingUpdater: true），
///   自动开始更新周期（异步，不阻塞启动）
/// - 渠道：仅官网直发 / Homebrew 构建有效；App Store 构建经 `#if !APP_STORE` 整体剔除
/// - 降级：未链接 Sparkle SDK（swiftc 直编开发构建）时全部方法为空操作，不崩溃（08 §3 模式）
@MainActor
final class NPUpdateService {

    /// 共享实例
    static let shared = NPUpdateService()

    /// Sparkle 更新控制器（仅链接 Sparkle 时存在）
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    private init() {
        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #endif
    }

    /// 检查更新（立即发起，对应菜单"检查更新…"）。
    func checkForUpdates() {
        #if canImport(Sparkle)
        updaterController.checkForUpdates(nil)
        #endif
    }

    /// 自动检查开关（Sparkle 持久化于 UserDefaults）。
    var isAutomaticCheckEnabled: Bool {
        get {
            #if canImport(Sparkle)
            return updaterController.updater.automaticallyChecksForUpdates
            #else
            return false
            #endif
        }
        set {
            #if canImport(Sparkle)
            updaterController.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// 上次检查时间（Sparkle 以 `SULastCheckTime` 写入 UserDefaults）。
    var lastCheckDate: Date? {
        #if canImport(Sparkle)
        return UserDefaults.standard.object(forKey: "SULastCheckTime") as? Date
        #else
        return nil
        #endif
    }
}

#endif
