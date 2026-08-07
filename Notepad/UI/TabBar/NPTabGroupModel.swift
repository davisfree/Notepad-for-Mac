//
//  NPTabGroupModel.swift
//  Notepad
//
//  Created by Notepad Team on 2026-08-02.
//  Copyright © 2026 Notepad for macOS Contributors. All rights reserved.
//

import Foundation

/// 标签组模型（纯逻辑，无 UI 依赖，可无 UI 测试）。
///
/// 只维护标识符列表与选中索引；文档与控制器映射由 `NPTabBarController` 持有。
struct NPTabGroupModel {

    // MARK: - 常量

    /// 拖出窗口判定的默认垂直阈值（`02_UI_DESIGN.md` 5.1：20pt）
    static let defaultDragOutThreshold: CGFloat = 20.0

    // MARK: - 状态

    /// 标签标识符列表（与视图顺序一致）
    private(set) var identifiers: [UUID] = []
    /// 当前选中索引（空组为 -1）
    private(set) var selectedIndex: Int = -1

    /// 标签数量
    var count: Int {
        identifiers.count
    }

    // MARK: - 增删

    /// 追加标签并选中（对齐 Win11：新标签立即成为当前标签）。
    /// - Parameter identifier: 标签标识符
    /// - Returns: 新标签索引
    @discardableResult
    mutating func append(_ identifier: UUID) -> Int {
        identifiers.append(identifier)
        selectedIndex = identifiers.count - 1
        return selectedIndex
    }

    /// 移除标签并修正选中索引（移除项在当前项之前则前移；移除当前项则选中后继或前驱；空组为 -1）。
    /// - Parameter index: 标签索引（越界忽略）
    mutating func remove(at index: Int) {
        guard identifiers.indices.contains(index) else {
            return
        }
        identifiers.remove(at: index)
        if identifiers.isEmpty {
            selectedIndex = -1
        } else if index < selectedIndex {
            selectedIndex -= 1
        } else if index == selectedIndex {
            selectedIndex = min(index, identifiers.count - 1)
        }
    }

    /// 清空全部标签（关窗摘除路径）。
    mutating func removeAll() {
        identifiers.removeAll()
        selectedIndex = -1
    }

    // MARK: - 排序与选择

    /// 移动标签（拖拽排序；越界或同位忽略）。
    /// - Parameters:
    ///   - source: 源索引
    ///   - destination: 目标索引
    mutating func move(from source: Int, to destination: Int) {
        guard identifiers.indices.contains(source), identifiers.indices.contains(destination),
              source != destination else {
            return
        }
        let item = identifiers.remove(at: source)
        identifiers.insert(item, at: destination)
        if selectedIndex == source {
            selectedIndex = destination
        } else if source < selectedIndex, destination >= selectedIndex {
            selectedIndex -= 1
        } else if source > selectedIndex, destination <= selectedIndex {
            selectedIndex += 1
        }
    }

    /// 选中标签（越界忽略）。
    /// - Parameter index: 目标索引
    mutating func select(_ index: Int) {
        guard identifiers.indices.contains(index) else {
            return
        }
        selectedIndex = index
    }

    // MARK: - 拖出判定

    /// 拖出窗口判定：拖拽点超出标签栏区域超过阈值（任意方向，02 §5.1 的 20pt）。
    /// - Parameters:
    ///   - point: 拖拽点（标签栏坐标系）
    ///   - bounds: 标签栏 bounds
    ///   - threshold: 阈值（默认 20pt）
    /// - Returns: 是否应判定为拖出窗口
    static func isDragOut(point: NSPoint, in bounds: NSRect, threshold: CGFloat = defaultDragOutThreshold) -> Bool {
        !bounds.insetBy(dx: -threshold, dy: -threshold).contains(point)
    }
}
