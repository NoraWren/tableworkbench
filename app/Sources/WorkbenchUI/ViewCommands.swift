import SwiftUI

/// 视图菜单：侧栏、检查器、SQL 抽屉。状态都存在 UserDefaults 里，菜单和界面共用同一份。
public struct ViewCommands: Commands {
    @AppStorage("sidebarShown") private var sidebarShown = true
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("sqlShown") private var sqlShown = false
    public init() {}

    public var body: some Commands {
        CommandMenu("视图") {
            toggle(.toggleSidebar, isOn: sidebarShown) { sidebarShown.toggle() }
            toggle(.toggleInspector, isOn: inspectorShown) { inspectorShown.toggle() }
            toggle(.toggleSQL, isOn: sqlShown) { sqlShown.toggle() }
        }
    }

    private func toggle(_ id: MenuItem.ID, isOn: Bool, action: @escaping () -> Void) -> some View {
        let item = MenuCatalog.item(id)!
        return Button(MenuCatalog.viewTitle(id, isOn: isOn), action: action)
            .keyboardShortcut(item.keyboardShortcut)
    }
}

