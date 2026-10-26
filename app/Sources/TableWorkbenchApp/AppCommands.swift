import SwiftUI

/// 菜单栏和界面之间的命令总线。界面负责填动作，菜单只读可用状态。
@MainActor
final class CommandBus: ObservableObject {
    static let shared = CommandBus()

    @Published var hasFile = false
    @Published var canExport = false
    @Published var canRunSQL = false
    @Published var hasSQLText = false
    @Published var canAnalyze = false

    var open: () -> Void = {}
    var export: () -> Void = {}
    var closeFile: () -> Void = {}
    var runSQL: () -> Void = {}
    var newQuery: () -> Void = {}
    var analyze: () -> Void = {}

    private init() {}
}

struct FileCommands: Commands {
    @ObservedObject private var bus = CommandBus.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开文件…") { bus.open() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .importExport) {
            Button("导出…") { bus.export() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!bus.canExport)
            Button("关闭文件") { bus.closeFile() }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(!bus.hasFile)
        }
    }
}

struct QueryCommands: Commands {
    @ObservedObject private var bus = CommandBus.shared

    var body: some Commands {
        CommandMenu("查询") {
            Button("运行") { bus.runSQL() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!bus.canRunSQL)
            Button("取消") {}
                .keyboardShortcut(".", modifiers: .command)
                .disabled(true)
            Divider()
            Button("新建查询") { bus.newQuery() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!bus.hasFile)
            Divider()
            Button("一键分析") { bus.analyze() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!bus.canAnalyze)
        }
    }
}
