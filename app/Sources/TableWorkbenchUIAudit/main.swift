import AppKit
import SwiftUI
import DuckDBKit
import Features
import DataGrid
import ChartUI
import WorkbenchUI

// 把界面层的关键面板离线渲染成 PNG，在没有界面自动化时用来核对外观与状态。
// 用法：TableWorkbenchUIAudit <输出目录>

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/ui-audit")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let columns = [
    ColumnInfo(name: "订单号", displayName: "订单号", typeName: "VARCHAR", kind: .text),
    ColumnInfo(name: "客户名称", displayName: "客户名称", typeName: "VARCHAR", kind: .text),
    ColumnInfo(name: "区域", displayName: "区域", typeName: "VARCHAR", kind: .text),
    ColumnInfo(name: "城市", displayName: "城市", typeName: "VARCHAR", kind: .text),
    ColumnInfo(name: "渠道", displayName: "渠道", typeName: "VARCHAR", kind: .text),
    ColumnInfo(name: "金额", displayName: "金额", typeName: "BIGINT", kind: .integer),
    ColumnInfo(name: "数量", displayName: "数量", typeName: "BIGINT", kind: .integer)
]

func sampleResult(rowCount: Int, truncated: Bool, elapsed: Double) -> SQLResult {
    SQLResult(
        columns: columns,
        rows: [
            ["A-1", "甲公司", "华南", "广州", "直销", "1200", "3"],
            ["A-2", "乙公司", "华东", "上海", "线上", "980", "2"]
        ],
        rowCount: rowCount,
        elapsed: elapsed,
        truncated: truncated
    )
}

/// 用 NSHostingView 包真实的 SwiftUI 视图再抓位图：Button、TextField、Picker 都能画出来。
@MainActor
func render<Content: View>(
    _ name: String,
    size: NSSize,
    @ViewBuilder content: () -> Content
) throws {
    let host = NSHostingView(rootView: content())
    host.frame = NSRect(origin: .zero, size: size)

    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = host
    window.orderBack(nil)
    host.layoutSubtreeIfNeeded()
    // SwiftUI 首帧要等一轮 runloop 才布局完。
    RunLoop.current.run(until: Date().addingTimeInterval(0.45))
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw NSError(domain: "uiaudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "拿不到位图"])
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "uiaudit", code: 2, userInfo: [NSLocalizedDescriptionKey: "转 PNG 失败"])
    }
    let url = outputDirectory.appendingPathComponent(name + ".png")
    try png.write(to: url)
    print(name + ".png  " + "\(Int(size.width))×\(Int(size.height))  \(png.count / 1024) KB")
    window.orderOut(nil)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    do {
        try render("pivot", size: NSSize(width: 560, height: 400)) {
            PivotPanel(columns: columns) { _ in }
        }
        try render("pivot-filled", size: NSSize(width: 560, height: 460)) {
            PivotPanel(
                columns: columns,
                draft: {
                    let draft = PivotDraft()
                    draft.add("区域", to: .rows)
                    draft.add("渠道", to: .columns)
                    draft.add("金额", to: .values)
                    draft.setAggregate(.average, for: "金额")
                    return draft
                }()
            ) { _ in }
        }
        try render("filter", size: NSSize(width: 560, height: 320)) {
            FilterPanel(columns: columns, initial: nil) { _ in }
        }
        try render("sql-editor", size: NSSize(width: 760, height: 220)) {
            SQLEditor(
                state: SQLState(),
                isRunning: false,
                history: SQLHistoryStore(),
                snippets: SQLSnippetStore(),
                tables: ["data"],
                columns: columns.map(\.name)
            ) {}
        }
        try render("sql-result", size: NSSize(width: 760, height: 300)) {
            SQLResultView(result: sampleResult(rowCount: 2, truncated: false, elapsed: 0.031), title: "透视结果") {}
        }
        try render("sql-result-truncated", size: NSSize(width: 760, height: 260)) {
            SQLResultView(result: sampleResult(rowCount: 100_000, truncated: true, elapsed: 1.24), title: "查询结果") {}
        }
        try render("sql-result-empty", size: NSSize(width: 760, height: 220)) {
            SQLResultView(
                result: SQLResult(columns: columns, rows: [], rowCount: 0, elapsed: 0.012, truncated: false),
                title: "查询结果"
            ) {}
        }
        try render("settings", size: NSSize(width: 520, height: 320)) {
            SettingsView()
        }
    } catch {
        let message = "渲染失败：" + String(describing: error) + "\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
    exit(0)
}
