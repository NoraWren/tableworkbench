import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Features
import DataGrid
import DuckDBKit

private final class SheetPromptState: ObservableObject {
    @Published var isPresented = false
    @Published var url: URL?
    @Published var sheets: [String] = []
    @Published var selected = ""
}

private final class PopoverState: ObservableObject {
    @Published var filterShown = false
    @Published var pivotShown = false
}

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("sqlShown") private var sqlShown = false
    @StateObject private var popover = PopoverState()
    @StateObject private var sql = SQLState()
    @StateObject private var sheetPrompt = SheetPromptState()

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if sqlShown {
                    Divider()
                    SQLEditor(state: sql, isRunning: model.isRunningSQL) {
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
                    .keyboardShortcut("o", modifiers: .command)
                    .help("打开 CSV 或 TSV（Command+O）")

                    if let entry = model.selectedEntry {
                        Button {
                            popover.filterShown.toggle()
                        } label: {
                            Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                        }
                        .help("添加筛选条件")
                        .popover(isPresented: $popover.filterShown, arrowEdge: .bottom) {
                            FilterPanel(columns: entry.columns, initial: entry.filter) { filter in
                                model.applyFilter(entryID: entry.id, filter: filter)
                                popover.filterShown = false
                            }
                        }
                    }

                    if let entry = model.selectedEntry {
                        Button {
                            exportPanel(entry: entry)
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        .help("导出当前视图（Shift+Command+E）")

                        Button {
                            popover.pivotShown.toggle()
                        } label: {
                            Label("透视", systemImage: "square.grid.3x3")
                        }
                        .help("拖拽字段生成透视表")
                        .popover(isPresented: $popover.pivotShown, arrowEdge: .bottom) {
                            PivotPanel(columns: entry.columns) { spec in
                                model.runPivot(entryID: entry.id, spec: spec)
                                popover.pivotShown = false
                            }
                        }
                    }

                    Button {
                        sqlShown.toggle()
                    } label: {
                        Label("SQL", systemImage: "chevron.up.square")
                    }
                    .help("展开或收起 SQL 抽屉（Command+J）")
                    .keyboardShortcut("j", modifiers: .command)

                    Button {
                        inspectorShown.toggle()
                    } label: {
                        Label("检查器", systemImage: "sidebar.right")
                    }
                    .help("显示或隐藏检查器（Command+Option+I）")
                    .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
        }
        .inspector(isPresented: $inspectorShown) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleOpen(urls: urls)
            return true
        }
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
        .overlay(alignment: .bottom) {
            if let error = model.error {
                ImportErrorCard(error: error) {
                    model.dismissError()
                }
                .frame(maxWidth: 620)
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
    }

    @ViewBuilder
    private var detailContent: some View {
        if let result = model.sqlResult {
            SQLResultView(result: result, title: model.resultTitle ?? "查询结果") {
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
                DataGridView(
                    columns: entry.columns,
                    rowCount: entry.resultCount,
                    sorts: entry.sort,
                    provider: { offset, size in
                        try entry.session.block(offset: offset, size: size)
                    },
                    onSortClick: { column, additive in
                        model.toggleSort(entryID: entry.id, column: column, additive: additive)
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
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType(filenameExtension: "parquet")
        ].compactMap { $0 }
        let defaultFormat = UserDefaults.standard.string(forKey: "defaultExportFormat") ?? "csv"
        panel.nameFieldStringValue = "export.\(defaultFormat)"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let format: ExportFormat = url.pathExtension.lowercased() == "parquet" ? .parquet : .csv
            model.export(entryID: entry.id, to: url, format: format)
        }
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["csv", "tsv", "tab", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            handleOpen(urls: panel.urls)
        }
    }
}

private struct SidebarView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        List(selection: $model.selection) {
            Section("数据源") {
                ForEach(model.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(entry.rowCount) 行 · \(entry.encoding.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
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
        VStack(spacing: 14) {
            Image(systemName: "tablecells")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("把一个 CSV 或 TSV 拖进来")
                .font(.title3)
            Text("支持逗号、制表符分隔，UTF-8 与 GBK 编码")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("数据不出本机")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
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
                            Button {
                                model.loadStats(entryID: entry.id, column: column.name)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(column.displayName)
                                            .fontWeight(model.statsColumn == column.name ? .semibold : .regular)
                                        Text(column.typeName)
                                            .font(.caption)
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
                        }
                    }
                    if let stats = model.columnStats {
                        Section("统计") {
                            statsRows(stats)
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

    @ViewBuilder
    private func statsRows(_ stats: ColumnStats) -> some View {
        LabeledContent("总行数", value: "\(stats.totalRows)")
        LabeledContent("空值", value: "\(stats.nullCount)（\(String(format: "%.1f", stats.nullRate * 100))%）")
        LabeledContent("去重值", value: "\(stats.distinctCount)")
        if let minValue = stats.minValue, let maxValue = stats.maxValue {
            LabeledContent("范围", value: "\(minValue) ~ \(maxValue)")
        }
        if let mean = stats.mean {
            LabeledContent("均值", value: format(mean))
        }
        if let median = stats.median {
            LabeledContent("中位数", value: format(median))
        }
        if let deviation = stats.standardDeviation {
            LabeledContent("标准差", value: format(deviation))
        }
        if !stats.histogram.isEmpty {
            let maxCount = max(1, stats.histogram.map(\.count).max() ?? 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(stats.histogram.enumerated()), id: \.offset) { _, bucket in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(width: 6, height: max(2, 40 * CGFloat(bucket.count) / CGFloat(maxCount)))
                }
            }
            .frame(height: 44)
        }
        if !stats.topValues.isEmpty {
            ForEach(stats.topValues, id: \.self) { item in
                HStack {
                    Text(item.value)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(item.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        if !stats.timeBuckets.isEmpty {
            ForEach(stats.timeBuckets.prefix(10), id: \.self) { bucket in
                HStack {
                    Text(bucket.label).font(.caption)
                    Spacer()
                    Text("\(bucket.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
