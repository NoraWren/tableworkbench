import SwiftUI
import AppKit
import Features

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let window = NSApp.windows.first else { return }
            window.setFrameAutosaveName("TableWorkbench.MainWindow")
            let visible = NSScreen.screens.map { $0.visibleFrame }
            if !visible.contains(where: { $0.intersects(window.frame) }) {
                window.setContentSize(NSSize(width: 1100, height: 760))
                window.center()
            }
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
    }
}
