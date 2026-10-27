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

/// 在视图树里找第一个 NSTableView，滚动与冻结的行为得直接对真表动手才能核对。
@MainActor
func findTableView(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView { return table }
    for subview in view.subviews {
        if let found = findTableView(in: subview) { return found }
    }
    return nil
}

/// 用 NSHostingView 包真实的 SwiftUI 视图再抓位图：Button、TextField、Picker 都能画出来。
@MainActor
func render<Content: View>(
    _ name: String,
    size: NSSize,
    dark: Bool = false,
    prepare: @MainActor (NSView) -> Void = { _ in },
    @ViewBuilder content: () -> Content
) throws {
    let host = NSHostingView(rootView: content())
    host.frame = NSRect(origin: .zero, size: size)
    // 外观要显式钉住，否则第二张图会沿用上一次的深色外观。
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.appearance = appearance
    // 离屏视图自己不画背景，真实窗口才有底。补的是系统解析出来的窗口底色，
    // 不是手调的白度，这样量出来的对比度才对得上真窗口。
    var backdrop = NSColor.white
    if let appearance {
        appearance.performAsCurrentDrawingAppearance {
            backdrop = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? backdrop
        }
    }
    host.wantsLayer = true
    host.layer?.backgroundColor = backdrop.cgColor

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
    // 首帧结束后再改滚动位置这类状态，改完要等重绘。
    prepare(host)
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))

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
        // 透视结果的多层表头：行维度冻结在左侧、纵向贯穿，列维度按渠道合并（R-PVT-04）。
        let pivotSpec = PivotSpec(
            rows: ["区域", "城市"],
            columns: ["渠道"],
            values: [
                PivotValue(column: "金额", aggregate: .sum),
                PivotValue(column: "数量", aggregate: .sum)
            ]
        )
        let pivotCombos = [["直销"], ["线上"], ["代理"]]
        let pivotHeader = PivotHeader.build(spec: pivotSpec, combos: pivotCombos)
        var pivotResultColumns = [
            ColumnInfo(name: "区域", displayName: "区域", typeName: "VARCHAR", kind: .text),
            ColumnInfo(name: "城市", displayName: "城市", typeName: "VARCHAR", kind: .text)
        ]
        for value in pivotSpec.values {
            for combo in pivotCombos {
                let name = value.title + " / " + combo.joined(separator: " / ")
                pivotResultColumns.append(
                    ColumnInfo(name: name, displayName: name, typeName: "BIGINT", kind: .integer)
                )
            }
        }
        try render("sql-result-pivot-header", size: NSSize(width: 860, height: 300)) {
            SQLResultView(
                result: SQLResult(
                    columns: pivotResultColumns,
                    rows: [
                        ["华南", "广州"] + (0..<6).map { String(1200 + $0 * 37) },
                        ["华东", "上海"] + (0..<6).map { String(980 + $0 * 21) }
                    ],
                    rowCount: 2,
                    elapsed: 0.044,
                    truncated: false
                ),
                title: "透视结果",
                header: pivotHeader
            ) {}
        }
        // 横向滚到右边：行维度列和表头必须留在原处（R-PVT-04 冻结）。
        try render(
            "sql-result-pivot-header-scrolled",
            size: NSSize(width: 620, height: 300),
            prepare: { root in
                guard let table = findTableView(in: root),
                      let scroll = table.enclosingScrollView else { return }
                scroll.contentView.scroll(to: NSPoint(x: 430, y: scroll.contentView.bounds.minY))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        ) {
            SQLResultView(
                result: SQLResult(
                    columns: pivotResultColumns,
                    rows: [
                        ["华南", "广州"] + (0..<6).map { String(1200 + $0 * 37) },
                        ["华东", "上海"] + (0..<6).map { String(980 + $0 * 21) }
                    ],
                    rowCount: 2,
                    elapsed: 0.044,
                    truncated: false
                ),
                title: "透视结果",
                header: pivotHeader
            ) {}
        }
        // 单行表头的普通查询，确认没有层级信息时还是原来那一行（回归）。
        try render("sql-result-flat-header", size: NSSize(width: 760, height: 240)) {
            SQLResultView(
                result: sampleResult(rowCount: 2, truncated: false, elapsed: 0.031),
                title: "查询结果",
                header: PivotHeader.singleRow(titles: columns.map(\.displayName))
            ) {}
        }
        try render("settings", size: NSSize(width: 520, height: 320)) {
            SettingsView()
        }

        // 检查器的统计块：深色下柱子、次要色文字、橙色冲突提示都得够对比度（R-INSP-03）。
        // 放在 List 里渲染，背景才是真实窗口里那层侧栏底色。
        let numericStats = ColumnStats(
            column: "金额",
            typeName: "BIGINT",
            kind: .integer,
            totalRows: 10_170_000,
            nullCount: 12_345,
            distinctCount: 5_335_465,
            minValue: "1.00",
            maxValue: "99999.00",
            mean: 4321.5,
            median: 2100,
            standardDeviation: 987.65,
            topValues: [TopValue(value: "8800", count: 42)],
            histogram: (0..<20).map { index in
                HistogramBucket(
                    lower: Double(index) * 5000,
                    upper: Double(index + 1) * 5000,
                    count: index % 5 == 0 ? 900_000 : 120_000 + index * 9_000
                )
            }
        )
        let conflictStats = ColumnStats(
            column: "mix",
            typeName: "VARCHAR",
            kind: .text,
            totalRows: 300_000,
            nullCount: 0,
            distinctCount: 150_001,
            minValue: "0",
            maxValue: "abc",
            mean: nil,
            median: nil,
            standardDeviation: nil,
            topValues: [TopValue(value: "abc", count: 150_000)],
            numericCount: 150_000,
            nonNumericExamples: ["abc"],
            numericSampleRows: 200_000,
            minLength: 1,
            maxLength: 3,
            whitespaceCount: 0
        )
        for (name, stats) in [("stats-number", numericStats), ("stats-conflict", conflictStats)] {
            for dark in [false, true] {
                let suffix = dark ? "-dark" : ""
                try render(name + suffix, size: NSSize(width: 300, height: 460), dark: dark) {
                    List {
                        Section {
                            ColumnStatsRows.build(stats)
                        } header: {
                            Text("统计").foregroundStyle(.secondary)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
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
        // 每种图都出浅色和深色两张：柱、线、饼块、网格线、文字都要逐张量对比度（R-VIZ-04）。
        for kind in ChartKind.allCases {
            for dark in [false, true] {
                let suffix = dark ? "-dark" : ""
                try render("chart-" + kind.rawValue + suffix, size: NSSize(width: 720, height: 360), dark: dark) {
                    ChartView(data: chartData(kind)) {}
                }
            }
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
