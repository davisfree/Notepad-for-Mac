//
//  NPFeedbackComposer.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-06.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 反馈邮件链接构造器（帮助 → 发送反馈…，06_RELEASE §7.2）。
///
/// 纯函数、无 I/O：把反馈渠道（邮件）封装为可测试的 URL 构造；
/// 版本信息可由调用方注入（测试），默认取自 Bundle / ProcessInfo。
enum NPFeedbackComposer {

    /// 构造反馈邮件链接（mailto）。
    /// - Parameters:
    ///   - recipient: 收件地址（默认取 `NPConstants.feedbackEmail`）
    ///   - appVersion: 应用版本描述（默认取自 Bundle，测试可注入）
    ///   - systemVersion: 系统版本描述（默认取自 ProcessInfo，测试可注入）
    ///   - subject: 邮件主题（默认取本地化文案，测试可注入）
    ///   - bodyFormat: 邮件正文模板（默认取本地化文案，须含两个 `%@` 占位符，测试可注入）
    /// - Returns: 可打开（`NSWorkspace.open`）的 mailto URL；构造失败时为 nil
    static func composeMailURL(recipient: String = NPConstants.feedbackEmail,
                               appVersion: String = defaultAppVersion(),
                               systemVersion: String = defaultSystemVersion(),
                               subject: String = defaultSubject(),
                               bodyFormat: String = defaultBodyFormat()) -> URL? {
        let body = String(format: bodyFormat, appVersion, systemVersion)
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// 默认邮件主题（本地化）。
    /// - Returns: 主题字符串
    private static func defaultSubject() -> String {
        NSLocalizedString("Feedback.MailSubject", comment: "反馈邮件主题")
    }

    /// 默认邮件正文模板（本地化，含版本占位符）。
    /// - Returns: 正文模板字符串
    private static func defaultBodyFormat() -> String {
        NSLocalizedString("Feedback.MailBody", comment: "反馈邮件正文模板")
    }

    /// 默认应用版本描述（如 "1.0 (1)"）。
    /// - Returns: 版本描述字符串
    private static func defaultAppVersion() -> String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// 默认系统版本描述（如 "15.0.0"）。
    /// - Returns: 系统版本字符串
    private static func defaultSystemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
