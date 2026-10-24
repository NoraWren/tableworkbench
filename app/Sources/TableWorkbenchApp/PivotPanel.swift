import SwiftUI
import Combine
import DuckDBKit

private final class PivotState: ObservableObject {
    @Published var rows: [String] = []
    @Published var columns: [String] = []
    @Published var values: [PivotValue] = []

    var spec: PivotSpec {
        PivotSpec(rows: rows, columns: columns, values: values)
    }

    var canRun: Bool {
        !rows.isEmpty && !values.isEmpty
    }

    func add(_ field: String, to area: PivotArea) {
        switch area {
        case .rows:
            if !rows.contains(field) { rows.append(field) }
        case .columns:
            if !columns.contains(field) { columns.append(field) }
        case .values:
            if !values.contains(where: { $0.column == field }) {
                values.append(PivotValue(column: field))
            }
        }
    }
}

private enum PivotArea: String {
    case rows = "行"
    case columns = "列"
    case values = "值"
}

struct PivotPanel: View {
    let columns: [ColumnInfo]
    let onRun: (PivotSpec) -> Void

    @StateObject private var state = PivotState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("透视表")
                .font(.headline)
            Text("把字段拖到行、列、值区域")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(columns, id: \.name) { column in
                        Text(column.displayName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                            .draggable(column.name) {
                                Text(column.displayName)
                            }
                    }
                }
            }

            dropArea("行", area: .rows, items: state.rows) { field in
                state.rows.removeAll { $0 == field }
            }
            dropArea("列", area: .columns, items: state.columns) { field in
                state.columns.removeAll { $0 == field }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("值").font(.caption).foregroundStyle(.secondary)
                ForEach(state.values.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(state.values[index].column)
                        Picker("聚合", selection: $state.values[index].aggregate) {
                            ForEach(PivotAggregate.allCases, id: \.self) { aggregate in
                                Text(aggregate.title).tag(aggregate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button {
                            state.values.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Color.clear
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .overlay(Text(state.values.isEmpty ? "拖字段到这里" : "").font(.caption).foregroundStyle(.secondary))
                    .dropDestination(for: String.self) { items, _ in
                        for item in items { state.add(item, to: .values) }
                        return true
                    }
            }

            HStack {
                Spacer()
                Button("生成透视") {
                    onRun(state.spec)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canRun)
            }
        }
        .padding(14)
        .frame(width: 560)
    }

    private func dropArea(
        _ title: String,
        area: PivotArea,
        items: [String],
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 4) {
                        Text(item).font(.caption)
                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                }
                Spacer()
            }
            .frame(minHeight: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
            .dropDestination(for: String.self) { dropped, _ in
                for item in dropped { state.add(item, to: area) }
                return true
            }
        }
    }
}
