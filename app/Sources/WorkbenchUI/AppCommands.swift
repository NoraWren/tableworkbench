import SwiftUI

/// 菜单栏和界面之间的命令总线。界面负责填动作，菜单只读可用状态。
@MainActor
public final class CommandBus: ObservableObject {
    public static let shared = CommandBus()

    @Published public var hasFile = false
    @Published public var canExport = false
    @Published public var canRunSQL = false
    @Published public var hasSQLText = false
    @Published public var canAnalyze = false
    @Published public var canCancel = false

    public var open: () -> Void = {}
    public var export: () -> Void = {}
    public var closeFile: () -> Void = {}
    public var runSQL: () -> Void = {}
    public var newQuery: () -> Void = {}
    public var analyze: () -> Void = {}
    public var showFilter: () -> Void = {}
    public var cancel: () -> Void = {}

    /// 测试要一份自己的总线来数调用次数，所以构造器不设成 private。
    public init() {}

    /// 菜单项到动作的唯一映射，菜单视图只负责呈现。
    public func perform(_ id: MenuItem.ID) {
        switch id {
        case .openFile: open()
        case .exportFile: export()
        case .closeFile: closeFile()
        case .runSQL: runSQL()
        case .newQuery: newQuery()
        case .autoAnalysis: analyze()
        case .findFilter: showFilter()
        case .cancelSQL: cancel()
        case .toggleSidebar, .toggleInspector, .toggleSQL: break
        }
    }

    /// 当前状态下这一项能不能点。
    public func isEnabled(_ id: MenuItem.ID) -> Bool {
        MenuCatalog.isEnabled(
            id,
            hasFile: hasFile,
            canExport: canExport,
            canRunSQL: canRunSQL,
            canAnalyze: canAnalyze,
            canCancel: canCancel
        )
    }
}

/// 从菜单表生成一个按钮，标题、快捷键、可用状态都查表。
private struct CatalogButton: View {
    let item: MenuItem
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .keyboardShortcut(item.keyboardShortcut)
            .disabled(!enabled)
    }
}

public struct FileCommands: Commands {
    @ObservedObject private var bus = CommandBus.shared
    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            CatalogButton(item: catalog(.openFile), title: catalog(.openFile).title, enabled: bus.isEnabled(.openFile)) {
                bus.perform(.openFile)
            }
        }
        CommandGroup(replacing: .importExport) {
            CatalogButton(item: catalog(.exportFile), title: catalog(.exportFile).title, enabled: bus.isEnabled(.exportFile)) {
                bus.perform(.exportFile)
            }
            CatalogButton(item: catalog(.closeFile), title: catalog(.closeFile).title, enabled: bus.isEnabled(.closeFile)) {
                bus.perform(.closeFile)
            }
        }
    }

    private func catalog(_ id: MenuItem.ID) -> MenuItem {
        MenuCatalog.item(id)!
    }
}

public struct QueryCommands: Commands {
    @ObservedObject private var bus = CommandBus.shared
    public init() {}

    public var body: some Commands {
        CommandMenu("查询") {
            CatalogButton(item: catalog(.runSQL), title: catalog(.runSQL).title, enabled: bus.isEnabled(.runSQL)) {
                bus.perform(.runSQL)
            }
            CatalogButton(item: catalog(.cancelSQL), title: catalog(.cancelSQL).title, enabled: bus.isEnabled(.cancelSQL)) {
                bus.perform(.cancelSQL)
            }
            Divider()
            CatalogButton(item: catalog(.newQuery), title: catalog(.newQuery).title, enabled: bus.isEnabled(.newQuery)) {
                bus.perform(.newQuery)
            }
            Divider()
            CatalogButton(item: catalog(.autoAnalysis), title: catalog(.autoAnalysis).title, enabled: bus.isEnabled(.autoAnalysis)) {
                bus.perform(.autoAnalysis)
            }
        }
    }

    private func catalog(_ id: MenuItem.ID) -> MenuItem {
        MenuCatalog.item(id)!
    }
}

/// 编辑菜单里的查找，Command+F 打开筛选面板（R-SHELL-02）。
public struct FindCommands: Commands {
    @ObservedObject private var bus = CommandBus.shared
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .textEditing) {
            CatalogButton(item: item, title: item.title, enabled: bus.isEnabled(.findFilter)) {
                bus.perform(.findFilter)
            }
        }
    }

    private var item: MenuItem {
        MenuCatalog.item(.findFilter)!
    }
}

