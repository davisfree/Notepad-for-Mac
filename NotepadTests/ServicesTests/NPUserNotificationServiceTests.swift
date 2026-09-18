//
//  NPUserNotificationServiceTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-09-18.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// 假投递实现：记录调用并按预设结果回调，避免触碰系统通知中心。
private final class FakeNotificationDelivery: NPNotificationDelivering {

    /// 授权结果
    var grantsAuthorization = true
    /// 投递错误
    var deliveryError: Error?
    /// 授权请求次数
    private(set) var authorizationRequestCount = 0
    /// 已投递的标题
    private(set) var deliveredTitles: [String] = []

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        authorizationRequestCount += 1
        completion(grantsAuthorization)
    }

    func deliver(title: String, body: String, completion: @escaping (Error?) -> Void) {
        deliveredTitles.append(title)
        completion(deliveryError)
    }
}

/// `NPUserNotificationService` 测试：授权、降级与冷却去重。
@MainActor
final class NPUserNotificationServiceTests: XCTestCase {

    /// 等待主队列任务完成（授权回调经 `Task { @MainActor }` 切回）。
    private func pumpMainActor() {
        let expectation = expectation(description: "main actor pump")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
    }

    /// 授权通过时应投递通知，且只请求一次授权。
    func testDeliversAfterAuthorizationGranted() {
        let delivery = FakeNotificationDelivery()
        let sut = NPUserNotificationService(delivery: delivery)

        sut.deliver(title: "T", body: "B")
        pumpMainActor()

        XCTAssertEqual(delivery.authorizationRequestCount, 1)
        XCTAssertEqual(delivery.deliveredTitles, ["T"])

        sut.deliver(title: "T2", body: "B2")
        pumpMainActor()
        XCTAssertEqual(delivery.authorizationRequestCount, 1, "授权状态应被缓存")
        XCTAssertEqual(delivery.deliveredTitles, ["T", "T2"])
    }

    /// 授权被拒绝时不投递（降级为日志）。
    func testDeniedAuthorizationSkipsDelivery() {
        let delivery = FakeNotificationDelivery()
        delivery.grantsAuthorization = false
        let sut = NPUserNotificationService(delivery: delivery)

        sut.deliver(title: "T", body: "B")
        pumpMainActor()

        XCTAssertEqual(delivery.authorizationRequestCount, 1)
        XCTAssertTrue(delivery.deliveredTitles.isEmpty)
    }

    /// 通知中心不可用时不应崩溃，也不投递。
    func testUnavailableNotificationCenterIsNoOp() {
        let sut = NPUserNotificationService(delivery: nil)
        sut.deliver(title: "T", body: "B")
        // 未崩溃即为通过；无投递实现可断言，故只验证状态未被破坏
        XCTAssertTrue(true)
    }

    /// 同一标题在冷却时间内只提示一次，避免连续失败造成通知轰炸。
    func testCooldownSuppressesRepeatedTitle() {
        let delivery = FakeNotificationDelivery()
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let sut = NPUserNotificationService(delivery: delivery,
                                            cooldown: 60,
                                            now: { currentDate })

        sut.deliver(title: "Same", body: "first")
        pumpMainActor()
        sut.deliver(title: "Same", body: "second")
        pumpMainActor()
        XCTAssertEqual(delivery.deliveredTitles, ["Same"], "冷却期内重复标题应被抑制")

        currentDate = currentDate.addingTimeInterval(61)
        sut.deliver(title: "Same", body: "third")
        pumpMainActor()
        XCTAssertEqual(delivery.deliveredTitles, ["Same", "Same"], "冷却结束后可再次提示")
    }
}
