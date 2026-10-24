import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Features
import DataGrid
import DuckDBKit

private final class PopoverState: ObservableObject {
    @Published var filterShown = false
}

struct ContentView: View {
    @ObservedObject var model: WorkspaceModel
    @AppStorage("inspectorShown") private var inspectorShown = true
    @AppStorage("sqlShown") private var sqlShown = false
    @StateObject private var popover = PopoverState()
    @StateObject private var sql = SQLState()

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
            InspectorView(entry: model.selectedEntry)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.open(urls: urls)
            return true
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
            SQLResultView(result: result) {
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

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["csv", "tsv", "tab"].compactMap { UTType(filenameExtension: $0) }
        if panel.runModal() == .OK {
            model.open(urls: panel.urls)
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
    let entry: WorkspaceModel.Entry?

    var body: some View {
        Group {
            if let entry {
                List {
                    Section("文件") {
                        LabeledContent("名称", value: entry.displayName)
                        LabeledContent("行数", value: "\(entry.rowCount)")
                        LabeledContent("编码", value: entry.encoding.displayName)
                    }
                    Section("列") {
                        ForEach(entry.columns, id: \.displayName) { column in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(column.displayName)
                                    .fontWeight(.medium)
                                Text(column.typeName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 1)
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
