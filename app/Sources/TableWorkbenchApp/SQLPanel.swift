import SwiftUI
import Foundation
import DuckDBKit
import Features
import DataGrid

final class SQLState: ObservableObject {
    @Published var text = "SELECT * FROM data LIMIT 100"
}

private final class HistoryPanelState: ObservableObject {
    @Published var shown = false
    @Published var search = ""
}

struct SQLEditor: View {
    @ObservedObject var state: SQLState
    let isRunning: Bool
    @ObservedObject var history: SQLHistoryStore
    let onRun: () -> Void

    @StateObject private var panel = HistoryPanelState()

    var body: some View {
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
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("运行") {
                    onRun()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(isRunning)
            }
            TextEditor(text: $state.text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
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

struct SQLResultView: View {
    let result: SQLResult
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                Text("\(result.rowCount) 行 · \(String(format: "%.2f", result.elapsed)) 秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if result.truncated {
                    Text("只显示前 100000 行")
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

            if result.rowCount == 0 {
                Text("0 行")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DataGridView(
                    columns: result.columns,
                    rowCount: result.rowCount,
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
