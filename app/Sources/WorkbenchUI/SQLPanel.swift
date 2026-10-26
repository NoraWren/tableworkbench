import SwiftUI
import Foundation
import DuckDBKit
import Features
import DataGrid
import SQLEditorUI

public final class SQLState: ObservableObject {
    @Published public var text = "SELECT * FROM data LIMIT 100"
    public init() {}
}

private final class HistoryPanelState: ObservableObject {
    @Published var shown = false
    @Published var search = ""
}

private final class SnippetPanelState: ObservableObject {
    @Published var shown = false
    @Published var name = ""
}

public struct SQLEditor: View {
    @ObservedObject var state: SQLState
    let isRunning: Bool
    @ObservedObject var history: SQLHistoryStore
    @ObservedObject var snippets: SQLSnippetStore
    /// 当前会话的表名与列名，补全候选来自这里。
    var tables: [String] = ["data"]
    var columns: [String] = []
    let onRun: () -> Void

    @StateObject private var panel = HistoryPanelState()
    @StateObject private var snippetPanel = SnippetPanelState()

    public init(
        state: SQLState,
        isRunning: Bool,
        history: SQLHistoryStore,
        snippets: SQLSnippetStore,
        tables: [String] = ["data"],
        columns: [String] = [],
        onRun: @escaping () -> Void
    ) {
        self.state = state
        self.isRunning = isRunning
        self.history = history
        self.snippets = snippets
        self.tables = tables
        self.columns = columns
        self.onRun = onRun
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SQL")
                    .font(.headline)
                Text("只读 · 结果最多 10 万行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    panel.shown.toggle()
                } label: {
                    Label("历史", systemImage: "clock")
                }
                .popover(isPresented: $panel.shown) {
                    historyPanel
                }

                Button {
                    snippetPanel.shown.toggle()
                } label: {
                    Label("存为片段", systemImage: "bookmark")
                }
                .popover(isPresented: $snippetPanel.shown) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("存为片段").font(.headline)
                        TextField("片段名称", text: $snippetPanel.name)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Spacer()
                            Button("保存") {
                                snippets.save(name: snippetPanel.name, sql: state.text)
                                snippetPanel.name = ""
                                snippetPanel.shown = false
                            }
                            .disabled(snippetPanel.name.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(14)
                    .frame(width: 320)
                }
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("运行") {
                    onRun()
                }
                .disabled(isRunning)
            }
            SQLTextView(text: $state.text, columns: columns, tables: tables)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                .help("输入表名或列名前缀会弹出候选，Tab 或回车接受，Esc 关闭")
        }
        .padding(12)
    }

    private var historyPanel: some View {
        let results = history.search(panel.search)
        return VStack(alignment: .leading, spacing: 8) {
            TextField("搜索历史", text: $panel.search)
                .textFieldStyle(.roundedBorder)
            if results.isEmpty {
                Text("没有历史")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { entry in
                    Button {
                        state.text = entry.sql
                        panel.shown = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.sql)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                            Text(entry.date, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("清空") { history.clear() }
                Spacer()
            }
        }
        .padding(12)
        .frame(width: 440, height: 360)
    }
}

public struct SQLResultView: View {
    let result: SQLResult
    let title: String
    let onClose: () -> Void

    public init(result: SQLResult, title: String, onClose: @escaping () -> Void) {
        self.result = result
        self.title = title
        self.onClose = onClose
    }

    public var body: some View {
        let status = SQLResultStatus(result: result, title: title)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(status.headline)
                    .font(.headline)
                Text(status.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notice = status.truncationNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("返回数据") {
                    onClose()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if let placeholder = status.emptyPlaceholder {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataGridView(
                    columns: result.columns,
                    // 行数按实际拿到的行算：结果被截断时两者相等，
                    // 万一少了行也别在末尾刷一片假的 NULL。
                    rowCount: min(result.rowCount, result.rows.count),
                    provider: { offset, size in
                        let start = max(0, min(offset, result.rows.count))
                        let end = max(start, min(offset + size, result.rows.count))
                        return TableBlock(offset: start, rows: Array(result.rows[start..<end]))
                    },
                    onSortClick: { _, _ in },
                    onError: { _ in }
                )
            }
        }
    }
}

/// 结果网格上方的状态条：行数、耗时、截断提示。
public struct SQLResultHeader: View {
    let result: SQLResult
    let title: String

    public init(result: SQLResult, title: String) {
        self.result = result
        self.title = title
    }

    public var body: some View {
        let status = SQLResultStatus(result: result, title: title)
        HStack(spacing: 8) {
            Text(status.headline)
                .font(.headline)
            Text(status.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let notice = status.truncationNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

