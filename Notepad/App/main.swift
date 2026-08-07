//
//  main.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import AppKit

// 顶层代码为非隔离上下文；NSApplication 与 AppDelegate 均为 @MainActor，
// 应用入口天然运行在主线程，显式声明隔离语义（Swift 6 编译器要求）
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
