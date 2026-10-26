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
    dark: Bool = false,
    @ViewBuilder content: () -> Content
) throws {
    let host = NSHostingView(rootView: content())
    host.frame = NSRect(origin: .zero, size: size)
    if dark {
        // 深色模式靠外观换，不是靠 colorScheme 环境值，Canvas 里取到的次要色才跟着变。
        host.appearance = NSAppearance(named: .darkAqua)
        // 离屏视图自己不画背景，真实窗口才有深色底，这里补一层才看得出对比度。
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor
    }

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
        // 四个区域齐全、带一个筛选条件的透视面板（R-PVT-01）。
        try render("pivot-filter", size: NSSize(width: 560, height: 540)) {
            PivotPanel(
                columns: columns,
                draft: {
                    let draft = PivotDraft()
                    draft.add("区域", to: .rows)
                    draft.add("金额", to: .values)
                    draft.add("渠道", to: .filter)
                    draft.setFilter(FilterCondition(column: "渠道", op: .contains, value: "线上"))
                    return draft
                }()
            ) { _ in }
        }
        // 带“查看 SQL”的完整面板：确认新按钮和“生成透视”并排不挤（R-PVT-02）。
        try render("pivot-sql", size: NSSize(width: 560, height: 460)) {
            PivotPanel(
                columns: columns,
                draft: {
                    let draft = PivotDraft()
                    draft.add("区域", to: .rows)
                    draft.add("金额", to: .values)
                    return draft
                }(),
                onRun: { _ in },
                onShowSQL: { _ in }
            )
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

        // 四种图各来一张，确认 Canvas 画得出来、标题与图例不打架（R-VIZ-01）。
        let chartPoints = [
            ChartPoint(label: "华南", value: 5120),
            ChartPoint(label: "华东", value: 4380),
            ChartPoint(label: "华北", value: 2960),
            ChartPoint(label: "西南", value: 1740),
            ChartPoint(label: "东北", value: 860)
        ]
        func chartData(_ kind: ChartKind) -> ChartData {
            ChartData(
                kind: kind,
                title: "区域 · 金额 求和",
                points: kind == .line
                    ? chartPoints.sorted { $0.label < $1.label }
                    : chartPoints,
                total: chartPoints.reduce(0) { $0 + $1.value },
                maxValue: chartPoints.map(\.value).max() ?? 0,
                elapsed: 0.074,
                groupCount: chartPoints.count
            )
        }
        for kind in ChartKind.allCases {
            try render("chart-" + kind.rawValue, size: NSSize(width: 720, height: 360)) {
                ChartView(data: chartData(kind)) {}
            }
        }
        // 深色模式：柱、网格线、文字都要还看得清（R-VIZ-04）。
        try render("chart-bar-dark", size: NSSize(width: 720, height: 360), dark: true) {
            ChartView(data: chartData(.bar)) {}
        }
        // 单分组与空结果两种边界。
        try render("chart-single", size: NSSize(width: 720, height: 360)) {
            ChartView(
                data: ChartData(
                    kind: .bar,
                    title: "城市 · 金额 求和",
                    points: [ChartPoint(label: "上海", value: 100)],
                    total: 100,
                    maxValue: 100,
                    elapsed: 0.012,
                    groupCount: 1
                )
            ) {}
        }
        try render("chart-empty", size: NSSize(width: 720, height: 320)) {
            ChartView(
                data: ChartData(
                    kind: .bar,
                    title: "区域 · 金额 求和",
                    points: [],
                    total: 0,
                    maxValue: 0,
                    elapsed: 0.004,
                    groupCount: 0
                )
            ) {}
        }
    } catch {
        let message = "渲染失败：" + String(describing: error) + "\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
    exit(0)
}
