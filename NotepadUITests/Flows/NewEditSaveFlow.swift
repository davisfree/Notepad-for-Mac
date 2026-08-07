//
//  NewEditSaveFlow.swift
//  NotepadUITests
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import XCTest

/// 新建 → 编辑 → 保存主流程 UI 测试。
final class NewEditSaveFlow: XCTestCase {

    /// 冒烟测试：应用可启动。
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
}
