//
//  NPCrashReporter.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-06.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// 崩溃日志脱敏器（01 §5 隐私约束：日志匿名化后上传，**不含文件路径与内容片段**）。
///
/// 纯函数、无 I/O，可独立单测（05_TEST_PLAN.md UT-CRASH-001 ~ 003）。
enum NPCrashSanitizer {

    /// 脱敏占位符
    private static let placeholder = "<redacted>"

    /// 本机路径模式（运行时求值，避免硬编码绝对路径——07 §8.2）。
    private static var pathPatterns: [String] {
        [
            // `file://` URL 整体替换（其后跟随非空白/引号/括号字符）
            "file://[^\\s\\\"'<>\\)\\],;]*",
            // 用户主目录及其下全部子路径（escapedPattern 处理元字符，如 `.mac` 中的点）
            NSRegularExpression.escapedPattern(for: NSHomeDirectory()),
            // 临时目录（现代 macOS 位于主目录之外时仍能命中）
            NSRegularExpression.escapedPattern(for: NSTemporaryDirectory())
        ]
    }

    /// 脱敏：将本机路径（主目录/临时目录）与 `file://` URL 替换为占位符。
    /// - Parameter text: 原始文本
    /// - Returns: 脱敏后的文本
    static func sanitize(_ text: String) -> String {
        var result = text
        for pattern in pathPatterns {
            result = result.replacingOccurrences(of: pattern,
                                                 with: placeholder,
                                                 options: [.regularExpression])
        }
        return result
    }
}

/// 崩溃报告服务（04 §5.5；01 §1.2：Sentry，SPM 引入，懒加载初始化不阻塞冷启动）。
///
/// - 启动：`start()` 仅完成 Sentry 配置（Sentry 自身异步捕获与上报，不占用主线程）
/// - DSN：经 Info.plist `SentryDSN` 注入（发布构建填写真实 DSN；留空或未链接 SDK → 空操作）
/// - 隐私：`beforeSend` 统一经 `NPCrashSanitizer` 脱敏，日志不含文件路径与内容片段（01 §5）
/// - 降级：未链接 Sentry SDK（swiftc 直编开发构建）时为空操作，不崩溃、不报错（08 §3 模式）
final class NPCrashReporter {

    /// 共享实例
    static let shared = NPCrashReporter()

    private init() {}

    /// 启动崩溃监控（应用启动时调用一次，不阻塞主线程）。
    func start() {
        #if canImport(Sentry)
        guard let dsn = dsn(), !dsn.isEmpty else {
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false
            // 隐私约束（01 §5）：默认不采集 PII / 截图 / 视图层级
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableSwizzling = false
            options.tracesSampleRate = 0.0
            // 崩溃日志脱敏：消息与异常值中的本机路径 / file:// URL 一律替换
            options.beforeSend = { event in
                if let message = event.message {
                    event.message = SentryMessage(formatted: NPCrashSanitizer.sanitize(message.formatted))
                }
                event.exceptions = event.exceptions?.map { exception in
                    if let value = exception.value {
                        exception.value = NPCrashSanitizer.sanitize(value)
                    }
                    return exception
                }
                return event
            }
        }
        #endif
    }

    /// 读取 Sentry DSN（Info.plist `SentryDSN`；开发构建留空 → 不启动）。
    /// - Returns: DSN 字符串（未配置时为 nil）
    private func dsn() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String
    }
}
