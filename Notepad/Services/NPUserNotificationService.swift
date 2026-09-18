//
//  NPUserNotificationService.swift
//  Notepad
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation
import UserNotifications
import os

/// 通知投递抽象。
///
/// 隔离系统通知中心，便于测试注入假实现；同时让"通知中心不可用"成为可表达的正常状态
/// （非 bundle 进程无法创建 `UNUserNotificationCenter`）。
protocol NPNotificationDelivering: AnyObject {
    /// 请求通知授权。
    /// - Parameter completion: 结果回调（授权是否通过）
    func requestAuthorization(completion: @escaping (Bool) -> Void)

    /// 投递一条本地通知。
    /// - Parameters:
    ///   - title: 标题
    ///   - body: 正文
    ///   - completion: 完成回调（失败时返回错误）
    func deliver(title: String, body: String, completion: @escaping (Error?) -> Void)
}

/// 基于 `UserNotifications` 的系统投递实现。
final class NPSystemNotificationDelivery: NPNotificationDelivering {

    /// 系统通知中心
    private let center: UNUserNotificationCenter

    /// 以系统通知中心创建。
    /// - Parameter center: 通知中心
    init(center: UNUserNotificationCenter) {
        self.center = center
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert]) { granted, _ in
            completion(granted)
        }
    }

    func deliver(title: String, body: String, completion: @escaping (Error?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request, withCompletionHandler: completion)
    }
}

/// 用户可见提示的投递服务（会话缓存失败、恢复冲突）。
///
/// 设计要点（`01_TECH_SPEC.md` 3.5）：
/// - 提示为**非模态**，不打断输入，也不影响保存流程；
/// - 通知中心不可用（非 bundle 进程）或用户拒绝授权时降级为统一日志；
/// - 同一标题在冷却时间内只提示一次，避免连续缓存失败造成通知轰炸；
/// - 日志只含提示文案，不含文件路径与内容片段。
@MainActor
final class NPUserNotificationService {

    // MARK: - 单例

    /// 共享实例（生产路径；测试注入独立实例）
    static let shared = NPUserNotificationService()

    // MARK: - 常量

    /// 同一标题的重复提示冷却时间（秒）
    static let defaultCooldown: TimeInterval = 60

    // MARK: - 授权状态

    private enum AuthorizationState {
        /// 尚未请求
        case unknown
        /// 已授权
        case granted
        /// 已拒绝
        case denied
    }

    // MARK: - 属性

    /// 投递实现；nil 表示通知中心不可用（仅日志）
    private let delivery: NPNotificationDelivering?
    /// 授权状态（首次投递时惰性请求，避免启动即弹系统授权框）
    private var authorizationState: AuthorizationState = .unknown
    /// 各标题最近一次实际提示时间（冷却去重）
    private var lastDeliveryDates: [String: Date] = [:]
    /// 重复提示冷却时间
    private let cooldown: TimeInterval
    /// 统一日志（降级通道）
    private let logger: Logger
    /// 当前时间提供者（测试可控）
    private let now: () -> Date

    // MARK: - 初始化

    /// 以系统通知中心创建（单例入口）。
    convenience init() {
        self.init(delivery: Self.makeSystemDelivery())
    }

    /// 注入投递实现创建（测试用）。
    /// - Parameters:
    ///   - delivery: 投递实现；传 nil 模拟通知中心不可用
    ///   - cooldown: 重复提示冷却时间
    ///   - now: 当前时间提供者
    init(delivery: NPNotificationDelivering?,
         cooldown: TimeInterval = NPUserNotificationService.defaultCooldown,
         now: @escaping () -> Date = Date.init) {
        self.delivery = delivery
        self.cooldown = cooldown
        self.now = now
        self.logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.notepadmac.Notepad",
                             category: "notifications")
    }

    // MARK: - 投递

    /// 投递用户提示；不可用或未授权时写入日志。
    /// - Parameters:
    ///   - title: 标题
    ///   - body: 正文
    func deliver(title: String, body: String) {
        let current = now()
        if let lastDate = lastDeliveryDates[title],
           current.timeIntervalSince(lastDate) < cooldown {
            return
        }
        guard let delivery else {
            logFallback(title: title, body: body, reason: "notification center unavailable")
            return
        }
        switch authorizationState {
        case .granted:
            post(delivery: delivery, title: title, body: body, at: current)
        case .denied:
            logFallback(title: title, body: body, reason: "authorization denied")
        case .unknown:
            delivery.requestAuthorization { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.authorizationState = granted ? .granted : .denied
                    if granted {
                        self.post(delivery: delivery, title: title, body: body, at: current)
                    } else {
                        self.logFallback(title: title, body: body, reason: "authorization denied")
                    }
                }
            }
        }
    }

    // MARK: - 私有

    /// 创建系统投递实现；非 bundle 进程（无 bundle identifier）返回 nil——
    /// 此时创建 `UNUserNotificationCenter` 会抛异常，必须提前规避。
    /// - Returns: 投递实现或 nil
    private static func makeSystemDelivery() -> NPNotificationDelivering? {
        guard Bundle.main.bundleIdentifier != nil else {
            return nil
        }
        return NPSystemNotificationDelivery(center: .current())
    }

    /// 实际投递并记录时间；失败降级为日志。
    private func post(delivery: NPNotificationDelivering, title: String, body: String, at date: Date) {
        lastDeliveryDates[title] = date
        delivery.deliver(title: title, body: body) { [weak self] error in
            guard error != nil else {
                return
            }
            Task { @MainActor [weak self] in
                self?.logFallback(title: title, body: body, reason: "delivery failed")
            }
        }
    }

    /// 降级：写入统一日志（只含提示文案，不含文件路径与内容）。
    private func logFallback(title: String, body: String, reason: String) {
        logger.warning("Notification not shown (\(reason, privacy: .public)): \(title, privacy: .public) - \(body, privacy: .public)")
    }
}
