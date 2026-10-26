import SwiftUI
import Combine
import DuckDBKit

/// 视图状态只是把 PivotDraft 包一层，让 SwiftUI 能观察到变化。
private final class PivotState: ObservableObject {
    let draft: PivotDraft

    init(seeding source: PivotDraft? = nil) {
        let draft = PivotDraft()
        if let source {
            // 复制一份，别让面板改到外面那份。
            for field in source.rows { draft.add(field, to: .rows) }
            for field in source.columns { draft.add(field, to: .columns) }
            for value in source.values {
                draft.add(value.column, to: .values)
                draft.setAggregate(value.aggregate, for: value.column)
            }
            for condition in source.filters {
                draft.add(condition.column, to: .filter)
                draft.setFilter(condition)
            }
        }
        self.draft = draft
    }

    var rows: [String] { draft.rows }
    var columns: [String] { draft.columns }
    var values: [PivotValue] { draft.values }
    var filters: [FilterCondition] { draft.filters }
    var canRun: Bool { draft.canRun }
    var blockedHint: String? { draft.blockedHint }
    var spec: PivotSpec { draft.spec }

    func add(_ field: String, to area: PivotDraft.Area) {
        objectWillChange.send()
        draft.add(field, to: area)
    }

    func remove(_ field: String, from area: PivotDraft.Area) {
        objectWillChange.send()
        draft.remove(field, from: area)
    }

    func removeValue(at index: Int) {
        objectWillChange.send()
        draft.removeValue(at: index)
    }

    func setAggregate(_ aggregate: PivotAggregate, for field: String) {
        objectWillChange.send()
        draft.setAggregate(aggregate, for: field)
    }

    func setFilter(_ condition: FilterCondition) {
        objectWillChange.send()
        draft.setFilter(condition)
    }

    func removeFilter(at index: Int) {
        objectWillChange.send()
        draft.removeFilter(at: index)
    }
}

public struct PivotPanel: View {
    let columns: [ColumnInfo]
    let onRun: (PivotSpec) -> Void
    /// 点“查看 SQL”时把配置交给外面翻译成 SQL。R-PVT-02 要求透视结果能在 SQL 抽屉里复现。
    let onShowSQL: ((PivotSpec) -> Void)?

    @StateObject private var state: PivotState

    public init(
        columns: [ColumnInfo],
        draft: PivotDraft? = nil,
        onRun: @escaping (PivotSpec) -> Void,
        onShowSQL: ((PivotSpec) -> Void)? = nil
    ) {
        self.columns = columns
        _state = StateObject(wrappedValue: PivotState(seeding: draft))
        self.onRun = onRun
        self.onShowSQL = onShowSQL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("透视表")
                .font(.headline)
            Text("把字段拖到行、列、值区域，可以再放一个到筛选")
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
                state.remove(field, from: .rows)
            }
            dropArea("列", area: .columns, items: state.columns) { field in
                state.remove(field, from: .columns)
            }

            filterArea

            VStack(alignment: .leading, spacing: 6) {
                Text("值").font(.caption).foregroundStyle(.secondary)
                ForEach(state.values.indices, id: \.self) { index in
                    HStack(spacing: 8) {
                        Text(state.values[index].column)
                        Picker("聚合", selection: Binding(
                            get: { state.values[index].aggregate },
                            set: { state.setAggregate($0, for: state.values[index].column) }
                        )) {
                            ForEach(PivotAggregate.allCases, id: \.self) { aggregate in
                                Text(aggregate.title).tag(aggregate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button {
                            state.removeValue(at: index)
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
                if let hint = state.blockedHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let onShowSQL {
                    Button("查看 SQL") {
                        onShowSQL(state.spec)
                    }
                    .disabled(!state.canRun)
                    .help("把这次透视翻译成 SQL，填进下面的 SQL 抽屉，可以改着跑")
                }
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
        area: PivotDraft.Area,
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

    /// 筛选区域：拖进来的字段各占一行，选运算符再填值，跟工具栏的筛选面板是一套口径。
    private var filterArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("筛选").font(.caption).foregroundStyle(.secondary)
            if state.filters.isEmpty {
                Color.clear
                    .frame(height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                    .overlay(Text("拖字段到这里").font(.caption).foregroundStyle(.secondary))
                    .dropDestination(for: String.self) { dropped, _ in
                        for item in dropped { state.add(item, to: .filter) }
                        return true
                    }
            } else {
                ForEach(Array(state.filters.enumerated()), id: \.element.column) { index, condition in
                    filterRow(index: index, condition: condition)
                }
                Color.clear
                    .frame(height: 20)
                    .dropDestination(for: String.self) { dropped, _ in
                        for item in dropped { state.add(item, to: .filter) }
                        return true
                    }
            }
        }
    }

    private func filterRow(index: Int, condition: FilterCondition) -> some View {
        HStack(spacing: 6) {
            Text(condition.column)
                .font(.caption)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
            Picker("运算符", selection: Binding(
                get: { condition.op },
                set: { operation in
                    var next = condition
                    next.op = operation
                    state.setFilter(next)
                }
            )) {
                ForEach(FilterOperator.allCases, id: \.self) { operation in
                    Text(operation.title).tag(operation)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            if condition.op.needsValue {
                TextField("值", text: Binding(
                    get: { condition.value },
                    set: { value in
                        var next = condition
                        next.value = value
                        state.setFilter(next)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            } else {
                Text("不用填值").font(.caption).foregroundStyle(.secondary)
            }

            Button {
                state.removeFilter(at: index)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}
