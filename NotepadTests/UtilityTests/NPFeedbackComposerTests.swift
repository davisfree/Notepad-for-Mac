//
//  NPFeedbackComposerTests.swift
//  NotepadTests
//
//  Created by Notepad Team on 2026-08-06.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest
@testable import Notepad

/// `NPFeedbackComposer` 测试（05_TEST_PLAN.md UT-FEED-001 ~ 003）。
final class NPFeedbackComposerTests: XCTestCase {

    /// 生成 mailto 链接：scheme 与收件人正确。
    func testComposesMailtoURL() throws {
        let url = try XCTUnwrap(NPFeedbackComposer.composeMailURL(
            recipient: "feedback@example.com",
            appVersion: "1.0 (1)",
            systemVersion: "14.5.0"
        ))
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.path, "feedback@example.com")
    }

    /// 主题与正文 query 参数齐全，正文含注入的版本信息。
    /// 单测 bundle 无本地化资源，主题/正文模板显式注入（生产代码默认取本地化文案）。
    func testContainsSubjectAndBody() throws {
        let url = try XCTUnwrap(NPFeedbackComposer.composeMailURL(
            recipient: "feedback@example.com",
            appVersion: "2.0 (10)",
            systemVersion: "15.3.1",
            subject: "Notepad Feedback",
            bodyFormat: "App: %@ | OS: %@ |"
        ))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let subject = try XCTUnwrap(items.first { $0.name == "subject" }?.value)
        let body = try XCTUnwrap(items.first { $0.name == "body" }?.value)
        XCTAssertEqual(subject, "Notepad Feedback")
        XCTAssertTrue(body.contains("2.0 (10)"))
        XCTAssertTrue(body.contains("15.3.1"))
    }

    /// 默认参数路径可用（收件人取 NPConstants.feedbackEmail，版本取自 Bundle/ProcessInfo）。
    func testComposesWithDefaults() throws {
        let url = try XCTUnwrap(NPFeedbackComposer.composeMailURL())
        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.path, NPConstants.feedbackEmail)
    }
}
