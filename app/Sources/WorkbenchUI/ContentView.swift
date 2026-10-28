import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Features
import DataGrid
import DuckDBKit
import ChartUI

private final class ComputedColumnState: ObservableObject {
    @Published var name = ""
    @Published var expression = ""
}

private final class SheetPromptState: ObservableObject {
    @Published var isPresented = false
    @Published var url: URL?
    @Published var sheets: [String] = []
    @Published var selected = ""
}

private final class PopoverState: ObservableObject {
    @Published var filterShown = false
    @Published var pivotShown = false
    @Published var computedShown = false
    @Published var chartShown = false
}

/// 导出前先选范围和格式，界面上同时看到每个范围会导出多少行。
private final class ExportSheetState: ObservableObject {
    enum Scope: String, CaseIterable, Identifiable {
        case view
        case all
        case selection
        var id: String { rawValue }
    }

    @Published var isPresented = false
    @Published var scope: Scope = .view
    @Published var format: ExportFormat = .csv
    private(set) var entryID: UUID?
    private(set) var viewRows = 0
    private(set) var allRows = 0
    private(set) var selectedRows = IndexSet()

    func present(entry: WorkspaceModel.Entry, selectedRows: IndexSet) {
        entryID = entry.id
        viewRows = entry.resultCount
        allRows = entry.rowCount
        self.selectedRows = selectedRows
        scope = .view
        let stored = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? "csv"
        format = stored == "parquet" ? .parquet : .csv
        isPresented = true
    }

    func label(for scope: Scope) -> String {
        switch scope {
        case .view: return "当前视图（\(viewRows.formatted()) 行）"
        case .all: return "全部行（\(allRows.formatted()) 行）"
        case .selection:
            return selectedRows.isEmpty
                ? "选中行（先选中要导出的行）"
                : "选中行（\(selectedRows.count.formatted()) 行）"
        }
    }

    var exportScope: ExportScope {
        switch scope {
        case .view: return .view
        case .all: return .all
        case .selection: return .rows(selectedRows)
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel
    @AppStorage("sidebarShown") private var sidebarShown = true
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("sqlShown") private var sqlShown = false
    @StateObject private var popover = PopoverState()
    @StateObject private var sql = SQLState()
    @StateObject private var sheetPrompt = SheetPromptState()
    @StateObject private var computed = ComputedColumnState()
    @StateObject private var snippets = SQLSnippetStore()
    @StateObject private var export = ExportSheetState()
    @StateObject private var chartPanel = ChartPanelState()

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            SidebarView(
                model: model,
                snippets: snippets.entries,
                onOpenSnippet: { snippet in
                    sql.text = snippet.sql
                    sqlShown = true
                },
                onDeleteSnippet: { snippet in
                    snippets.remove(id: snippet.id)
                }
            )
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if sqlShown {
                    Divider()
                    SQLEditor(
                        state: sql,
                        isRunning: model.isRunningSQL,
                        history: model.sqlHistory,
                        snippets: snippets,
                        tables: ["data"],
                        columns: model.selectedEntry?.columns.map(\.name) ?? []
                    ) {
                        if let entry = model.selectedEntry {
                            model.runSQL(entryID: entry.id, sql: sql.text)
                        }
                    }
                    .frame(height: 160)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: openPanel) {
                        Label("打开文件", systemImage: "folder")
                    }
                    .help("打开 CSV 或 TSV（Command+O）")

                    if let entry = model.selectedEntry {
                        Button {
                            popover.filterShown.toggle()
                        } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .help("添加筛选条件（Command+F）")
                        .popover(isPresented: $popover.filterShown, arrowEdge: .bottom) {
                            FilterPanel(columns: entry.columns, initial: entry.filter) { filter in
                                model.applyFilter(entryID: entry.id, filter: filter)
                                popover.filterShown = false
                            }
                        }
                    }

                    if let entry = model.selectedEntry {
                        Button {
                            popover.computedShown.toggle()
                        } label: {
                            Label("计算列", systemImage: "function")
                        }
                        .help("用表达式添加一列")
                        .popover(isPresented: $popover.computedShown, arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("计算列").font(.headline)
                                TextField("列名", text: $computed.name)
                                TextField("表达式，例如 amount * 1.06", text: $computed.expression)
                                HStack {
                                    Spacer()
                                    Button("添加") {
                                        model.addComputedColumn(
                                            entryID: entry.id,
                                            name: computed.name,
                                            expression: computed.expression
                                        )
                                        computed.name = ""
                                        computed.expression = ""
                                        popover.computedShown = false
                                    }
                                    .disabled(computed.name.isEmpty || computed.expression.isEmpty)
                                }
                            }
                            .padding(14)
                            .frame(width: 420)
                        }

                        Button {
                            exportPanel(entry: entry)
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                        .help("导出当前视图（Shift+Command+E）")

                        Button {
                            popover.pivotShown.toggle()
                        } label: {
                            Label("透视", systemImage: "square.grid.3x3")
                        }
                        .help("拖拽字段生成透视表")
                        .popover(isPresented: $popover.pivotShown, arrowEdge: .bottom) {
                            PivotPanel(
                                columns: entry.columns,
                                onRun: { spec in
                                    model.runPivot(entryID: entry.id, spec: spec)
                                    popover.pivotShown = false
                                },
                                onShowSQL: { spec in
                                    model.makePivotSQL(entryID: entry.id, spec: spec) { sql in
                                        guard let sql else { return }
                                        self.sql.text = sql
                                        self.sqlShown = true
                                        popover.pivotShown = false
                                    }
                                }
                            )
                        }

                        Button {
                            popover.chartShown.toggle()
                        } label: {
                            Label("图表", systemImage: "chart.bar")
                        }
                        .help("按一列分组画图")
                        .popover(isPresented: $popover.chartShown, arrowEdge: .bottom) {
                            ChartPanel(columns: entry.columns, state: chartPanel) { spec in
                                model.runChart(entryID: entry.id, spec: spec)
                                popover.chartShown = false
                            }
                        }

                        Button {
                            model.runAutoAnalysis(entryID: entry.id)
                        } label: {
                            Label("一键分析", systemImage: "wand.and.stars")
                        }
                        .help("自动挑几列，生成一组图")
                        .disabled(model.isAnalyzing)
                    }

                    Button {
                        sqlShown.toggle()
                    } label: {
                        Label("SQL", systemImage: "chevron.up.square")
                    }
                    .help("展开或收起 SQL 抽屉（Command+J）")

                    Button {
                        inspectorShown.toggle()
                    } label: {
                        Label("检查器", systemImage: "sidebar.right")
                    }
                    .help("显示或隐藏检查器（Command+Option+I）")
                }
            }
        }
        .inspector(isPresented: $inspectorShown) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        // 访达拖文件走窗口层接收，原因见 DropTarget.swift 顶部注释。
        .background(
            DropTargetInstaller { urls in
                handleOpen(urls: urls)
            }
            .frame(width: 0, height: 0)
        )
        .sheet(isPresented: $sheetPrompt.isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text("选择工作表").font(.headline)
                Picker("工作表", selection: $sheetPrompt.selected) {
                    ForEach(sheetPrompt.sheets, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                HStack {
                    Button("取消") { sheetPrompt.isPresented = false }
                    Spacer()
                    Button("全部导入（\(sheetPrompt.sheets.count) 个工作表）") {
                        if let url = sheetPrompt.url {
                            model.open(url: url, sheetNames: sheetPrompt.sheets)
                        }
                        sheetPrompt.isPresented = false
                    }
                    Button("打开") {
                        if let url = sheetPrompt.url {
                            model.open(urls: [url], sheetName: sheetPrompt.selected)
                        }
                        sheetPrompt.isPresented = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .sheet(isPresented: $export.isPresented) {
            ExportSheet(state: export) {
                let entryID = export.entryID
                let scope = export.exportScope
                let format = export.format
                export.isPresented = false
                // 等确认框收起来再弹保存面板，两个模态叠在一起会有一个卡住不显示。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    savePanel(entryID: entryID, format: format, scope: scope)
                }
            } onCancel: {
                export.isPresented = false
            }
        }
        .sheet(isPresented: rowDetailShown) {
            if let detail = model.rowDetail {
                RowDetailSheet(detail: detail) { model.dismissRowDetail() }
            }
        }
        .overlay(alignment: .bottom) {
            if let error = model.error {
                ImportErrorCard(error: error) {
                    model.dismissError()
                }
                .frame(maxWidth: 620)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if model.isLoading {
                ProgressView("正在打开…")
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.error != nil)
        .animation(.easeInOut(duration: 0.18), value: model.isLoading)
        .onAppear {
            configureCommands()
            OpenRequestBus.shared.handle = { urls in handleOpen(urls: urls) }
            let pending = OpenRequestBus.shared.pending
            if !pending.isEmpty {
                OpenRequestBus.shared.pending = []
                handleOpen(urls: pending)
            }
        }
        .onChange(of: model.selection) { _, _ in configureCommands() }
        .onChange(of: model.isRunningSQL) { _, _ in configureCommands() }
        .onChange(of: model.isAnalyzing) { _, _ in configureCommands() }
        .onReceive(model.$entries) { _ in configureCommands() }
    }

    private func configureCommands() {
        let bus = CommandBus.shared
        bus.hasFile = model.selectedEntry != nil
        bus.canExport = bus.hasFile
        bus.canRunSQL = bus.hasFile && !model.isRunningSQL
        bus.hasSQLText = !sql.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        bus.canAnalyze = bus.hasFile && !model.isAnalyzing
        bus.open = { openPanel() }
        bus.export = {
            if let entry = model.selectedEntry { exportPanel(entry: entry) }
        }
        bus.closeFile = { model.closeSelected() }
        bus.runSQL = {
            if let entry = model.selectedEntry {
                model.runSQL(entryID: entry.id, sql: sql.text)
            }
        }
        bus.newQuery = {
            sql.text = "SELECT * FROM data LIMIT 100"
            sqlShown = true
        }
        bus.analyze = {
            if let entry = model.selectedEntry {
                model.runAutoAnalysis(entryID: entry.id)
            }
        }
        bus.showFilter = {
            popover.filterShown = true
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarShown ? .all : .detailOnly },
            set: { sidebarShown = $0 != .detailOnly }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        if let charts = model.autoCharts {
            AutoAnalysisView(charts: charts) {
                model.clearAutoAnalysis()
            }
        } else if model.isAnalyzing {
            ProgressView("正在分析…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let chart = model.chartData {
            ChartView(data: chart) {
                model.clearChart()
            }
        } else if model.isBuildingChart {
            ProgressView("正在生成图表…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result = model.sqlResult {
            SQLResultView(
                result: result,
                title: model.resultTitle ?? "查询结果",
                header: model.pivotHeader
            ) {
                model.clearSQLResult()
            }
        } else if let entry = model.selectedEntry {
            VStack(spacing: 0) {
                if entry.columns.count > DataGridView.maxVisibleColumns {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                        Text("共 \(entry.columns.count) 列，默认显示前 \(DataGridView.defaultVisibleColumns) 列")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary)
                }
                HStack(spacing: 8) {
                    Text(entry.filter == nil
                         ? "\(entry.rowCount) 行"
                         : "\(entry.rowCount) 行中的 \(entry.resultCount) 行")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.isQuerying {
                        ProgressView()
                            .controlSize(.small)
                    }
                    if model.isExporting {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在导出…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = model.lastExportMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                if entry.resultCount == 0 {
                    Text("没有匹配的行")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                let shownColumns = model.shownColumns(for: entry)
                DataGridView(
                    columns: shownColumns,
                    rowCount: entry.resultCount,
                    sorts: entry.sort,
                    provider: { offset, size in
                        try entry.session.block(offset: offset, size: size, columns: shownColumns)
                    },
                    onSortClick: { column, additive in
                        model.toggleSort(entryID: entry.id, column: column, additive: additive)
                    },
                    onSelectionChange: { rows in
                        model.updateSelectedRows(rows)
                    },
                    onRowActivate: { row in
                        model.loadRowDetail(entryID: entry.id, row: row)
                    },
                    onError: { error in
                        let importError = (error as? ImportError) ?? ImportError.wrap(error, step: "读取数据")
                        Task { @MainActor in
                            model.report(importError)
                        }
                    }
                )
                .id("\(entry.id)-\(entry.queryVersion)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            EmptyStateView()
        }
    }

    private func handleOpen(urls: [URL]) {
        guard urls.count == 1,
              let url = urls.first,
              url.pathExtension.lowercased() == "xlsx",
              let sheets = try? XLSXConverter.sheets(at: url),
              sheets.count > 1 else {
            model.open(urls: urls)
            return
        }
        sheetPrompt.url = url
        sheetPrompt.sheets = sheets.map(\.name)
        sheetPrompt.selected = sheets[0].name
        sheetPrompt.isPresented = true
    }

    private func exportPanel(entry: WorkspaceModel.Entry) {
        export.present(entry: entry, selectedRows: model.selectedRows)
    }

    private var rowDetailShown: Binding<Bool> {
        Binding(
            get: { model.rowDetail != nil },
            set: { shown in
                if !shown { model.dismissRowDetail() }
            }
        )
    }

    private func savePanel(entryID: UUID?, format: ExportFormat, scope: ExportScope) {
        guard let entryID else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "parquet")
        ].compactMap { $0 }
        panel.nameFieldStringValue = "export.\(format.rawValue)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let chosen: ExportFormat = url.pathExtension.lowercased() == "parquet" ? .parquet : .csv
            model.export(entryID: entryID, to: url, format: chosen, scope: scope)
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["csv", "tsv", "tab", "xlsx", "parquet"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            handleOpen(urls: panel.urls)
        }
    }
}

/// 双击一行后的详情：竖排看全部字段，长文本不截断，可整行复制。
private struct RowDetailSheet: View {
    let detail: WorkspaceModel.RowDetail
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("第 \(detail.row + 1) 行").font(.headline)
                Spacer()
                Text("\(detail.fields.count) 个字段")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.fields) { field in
                        HStack(alignment: .top, spacing: 12) {
                            Text(field.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .trailing)
                            Text(field.value ?? "(空)")
                                .textSelection(.enabled)
                                .foregroundStyle(field.value == nil ? .tertiary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("复制这一行") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(detail.tsv, forType: .string)
                }
                Spacer()
                Button("关闭", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }
}

/// 导出确认框：先定范围和格式，再进保存面板。
private struct ExportSheet: View {
    @ObservedObject var state: ExportSheetState
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("导出").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(ExportSheetState.Scope.allCases) { scope in
                    let unavailable = scope == .selection && state.selectedRows.isEmpty
                    Button {
                        state.scope = scope
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: state.scope == scope ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(state.scope == scope ? Color.accentColor : Color.secondary)
                            Text(state.label(for: scope))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable)
                    .opacity(unavailable ? 0.45 : 1)
                }
            }

            if state.scope == .selection, state.selectedRows.isEmpty {
                Text("先在表格里选中要导出的行，这个选项才有内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("格式", selection: $state.format) {
                Text("CSV").tag(ExportFormat.csv)
                Text("Parquet").tag(ExportFormat.parquet)
            }
            .pickerStyle(.segmented)

            Text("导出的列与当前视图一致，计算列不导出。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("导出…", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.scope == .selection && state.selectedRows.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct SidebarView: View {
    @ObservedObject var model: WorkspaceModel
    let snippets: [SQLSnippet]
    let onOpenSnippet: (SQLSnippet) -> Void
    let onDeleteSnippet: (SQLSnippet) -> Void

    var body: some View {
        List(selection: $model.selection) {
            if !snippets.isEmpty {
                Section("SQL 片段") {
                    ForEach(snippets) { snippet in
                        Button {
                            onOpenSnippet(snippet)
                        } label: {
                            Text(snippet.name)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除") { onDeleteSnippet(snippet) }
                        }
                    }
                }
            }

            Section("数据源") {
                ForEach(model.entries) { entry in
                    HStack(spacing: 9) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 15)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(entry.rowCount) 行 · \(entry.encoding.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(entry.id)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if model.entries.isEmpty {
                VStack(spacing: 6) {
                    Text("还没有打开文件")
                        .font(.callout)
                    Text("拖入 CSV 或 TSV")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button("关闭当前文件") {
                model.closeSelected()
            }
            .disabled(model.selection == nil)
        }
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 112, height: 112)
                Image(systemName: "tablecells")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tint)
            }

            VStack(spacing: 8) {
                Text("把一个 CSV 或 TSV 拖进来")
                    .font(.system(size: 21, weight: .semibold))
                Text("支持 CSV、TSV、Parquet 和 Excel（xlsx）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                shortcutHint("⌘O", "打开")
                hintDivider
                shortcutHint("⌘J", "SQL")
                hintDivider
                shortcutHint("⇧⌘E", "导出")
            }
            .padding(.top, 2)

            Text("数据不出本机")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var hintDivider: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(width: 1, height: 12)
    }

    private func shortcutHint(_ keys: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct InspectorView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        Group {
            if let entry = model.selectedEntry {
                List {
                    Section("文件") {
                        LabeledContent("名称", value: entry.displayName)
                        LabeledContent("行数", value: "\(entry.rowCount)")
                        LabeledContent("编码", value: entry.encoding.displayName)
                    }
                    Section("列") {
                        ForEach(entry.columns, id: \.name) { column in
                            HStack(spacing: 6) {
                                Button {
                                    model.loadStats(entryID: entry.id, column: column.name)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(column.displayName)
                                                .fontWeight(model.statsColumn == column.name ? .semibold : .regular)
                                            Text(column.typeName)
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(.quaternary.opacity(0.55), in: Capsule())
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if model.statsColumn == column.name, model.columnStats != nil {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                if entry.displayColumns.count > DataGridView.maxVisibleColumns {
                                    let shown = model.isColumnShown(entryID: entry.id, column: column.name)
                                    Button {
                                        model.toggleColumn(entryID: entry.id, column: column.name)
                                    } label: {
                                        Image(systemName: shown ? "eye" : "eye.slash")
                                            .foregroundStyle(shown ? .secondary : .tertiary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(shown ? "隐藏这一列" : "显示这一列")
                                }
                            }
                        }
                    }
                    if let stats = model.columnStats {
                        // 系统默认的分组标题比正文还暗，深色下只有 2.69:1，达不到 AA。
                        // 显式取次要色，实测 5.91:1。
                        Section {
                            ColumnStatsRows.build(stats)
                        } header: {
                            Text("统计").foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("选中一个文件后显示列信息")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .listStyle(.sidebar)
    }
}
