import SwiftUI
import AppKit
import Features
import DuckDBKit

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let model = WorkspaceModel()
    private init() {}
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppEnvironment.shared.model.open(urls: urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let limitGB = UserDefaults.standard.integer(forKey: "cacheLimitGB")
        if limitGB > 0 {
            ParquetCache.shared.setLimitBytes(Int64(limitGB) * 1024 * 1024 * 1024)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let visible = NSScreen.screens.map { $0.visibleFrame }
            for window in NSApp.windows {
                if !visible.contains(where: { $0.intersects(window.frame) }) {
                    window.center()
                }
            }
            NSApp.windows
                .first(where: { $0.title == "本地表格工作台" })?
                .setFrameAutosaveName("TableWorkbench.MainWindow")
        }
    }
}

@main
struct TableWorkbenchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppEnvironment.shared.model

    var body: some Scene {
        Window("本地表格工作台", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
        }
    }
}
