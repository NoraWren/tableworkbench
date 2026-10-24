import SwiftUI
import Combine
import DuckDBKit

private final class FilterState: ObservableObject {
    @Published var join: FilterJoin
    @Published var conditions: [FilterCondition]

    init(group: FilterGroup, columns: [ColumnInfo]) {
        self.join = group.join
        self.conditions = group.conditions.isEmpty
            ? [FilterCondition(column: columns.first?.name ?? "", op: .equal)]
            : group.conditions
    }
}

struct FilterPanel: View {
    let columns: [ColumnInfo]
    let onApply: (FilterGroup?) -> Void

    @StateObject private var state: FilterState

    init(columns: [ColumnInfo], initial: FilterGroup?, onApply: @escaping (FilterGroup?) -> Void) {
        self.columns = columns
        self.onApply = onApply
        _state = StateObject(wrappedValue: FilterState(group: initial ?? FilterGroup(), columns: columns))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("筛选条件")
                .font(.headline)

            ForEach(state.conditions.indices, id: \.self) { index in
                row(at: index)
            }

            Button {
                addCondition()
            } label: {
                Label("添加条件", systemImage: "plus")
            }
            .disabled(state.conditions.count >= 10)

            Divider()

            Picker("组合方式", selection: $state.join) {
                Text(FilterJoin.and.title).tag(FilterJoin.and)
                Text(FilterJoin.or.title).tag(FilterJoin.or)
            }
            .pickerStyle(.segmented)

            HStack {
                Button("清除") { onApply(nil) }
                Spacer()
                Button("应用") { onApply(makeGroup()) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 560)
    }

    private func row(at index: Int) -> some View {
        HStack(spacing: 8) {
            Picker("列", selection: $state.conditions[index].column) {
                ForEach(columns, id: \.name) { column in
                    Text(column.displayName).tag(column.name)
                }
            }
            .labelsHidden()
            .frame(width: 130)

            Picker("运算符", selection: $state.conditions[index].op) {
                ForEach(FilterOperator.allCases, id: \.self) { op in
                    Text(op.title).tag(op)
                }
            }
            .labelsHidden()
            .frame(width: 90)

            if state.conditions[index].op.needsValue {
                TextField("值", text: $state.conditions[index].value)
                    .textFieldStyle(.roundedBorder)
            }
            if state.conditions[index].op.needsSecondValue {
                TextField("到", text: Binding(
                    get: { state.conditions[index].secondValue ?? "" },
                    set: { state.conditions[index].secondValue = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }

            Button {
                state.conditions.remove(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(state.conditions.count == 1)
        }
    }

    private func addCondition() {
        guard state.conditions.count < 10, let first = columns.first?.name else { return }
        state.conditions.append(FilterCondition(column: first, op: .equal))
    }

    private func makeGroup() -> FilterGroup? {
        let valid = state.conditions.filter { condition in
            if condition.op.needsValue && condition.value.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
            if condition.op.needsSecondValue && (condition.secondValue ?? "").isEmpty {
                return false
            }
            return true
        }
        guard !valid.isEmpty else { return nil }
        return FilterGroup(join: state.join, conditions: valid)
    }
}
