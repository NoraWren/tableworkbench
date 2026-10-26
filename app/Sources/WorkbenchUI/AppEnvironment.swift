import SwiftUI
import AppKit
import Features
import DuckDBKit

/// 全局状态入口。界面层单独成一个库，测试与离屏渲染可以直接拿到同一份模型。
@MainActor
public final class AppEnvironment {
    public static let shared = AppEnvironment()
    public let model = WorkspaceModel()
    private init() {}
}

/// Finder 打开文件的事件先交给界面层，界面还没起来就暂存。
@MainActor
public final class OpenRequestBus {
    public static let shared = OpenRequestBus()
    public var handle: (([URL]) -> Void)?
    public var pending: [URL] = []
    private init() {}
}

/// 可执行 target 只认这个门面，其余视图都在库内部。
public struct WorkbenchRootView: View {
    private let model: WorkspaceModel

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        ContentView(model: model)
    }
}
