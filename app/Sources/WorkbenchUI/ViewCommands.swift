import SwiftUI

/// 视图菜单：侧栏、检查器、SQL 抽屉。状态都存在 UserDefaults 里，菜单和界面共用同一份。
public struct ViewCommands: Commands {
    @AppStorage("sidebarShown") private var sidebarShown = true
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("sqlShown") private var sqlShown = false
    public init() {}

    public var body: some Commands {
        CommandMenu("视图") {
            Button(sidebarShown ? "隐藏侧栏" : "显示侧栏") {
                sidebarShown.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])

            Button(inspectorShown ? "隐藏检查器" : "显示检查器") {
                inspectorShown.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            Button(sqlShown ? "隐藏 SQL 抽屉" : "显示 SQL 抽屉") {
                sqlShown.toggle()
            }
            .keyboardShortcut("j", modifiers: .command)
        }
    }
}
