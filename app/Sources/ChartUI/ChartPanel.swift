import SwiftUI
import DuckDBKit

public final class ChartPanelState: ObservableObject {
    @Published public var kind: ChartKind = .bar
    @Published public var groupColumn = ""
    @Published public var measureColumn = ""
    @Published public var aggregate: PivotAggregate = .sum

    public init() {}
}

/// 建图配置：分组列 + 度量列 + 聚合 + 图表类型。
public struct ChartPanel: View {
    let columns: [ColumnInfo]
    @ObservedObject var state: ChartPanelState
    let onRun: (ChartSpec) -> Void

    public init(columns: [ColumnInfo], state: ChartPanelState, onRun: @escaping (ChartSpec) -> Void) {
        self.columns = columns
        self.state = state
        self.onRun = onRun
    }

    private var numericColumns: [ColumnInfo] {
        columns.filter { $0.kind.isNumeric }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("图表").font(.headline)
            Text("按一列分组，把另一列算成一个数，再画出来")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("图表类型", selection: $state.kind) {
                ForEach(ChartKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Picker("分组列", selection: $state.groupColumn) {
                    ForEach(columns, id: \.name) { column in
                        Text(column.displayName).tag(column.name)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker("度量列", selection: $state.measureColumn) {
                    ForEach(numericColumns, id: \.name) { column in
                        Text(column.displayName).tag(column.name)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Picker("聚合", selection: $state.aggregate) {
                    ForEach(PivotAggregate.allCases, id: \.self) { aggregate in
                        Text(aggregate.title).tag(aggregate)
                    }
                }
                .frame(width: 160)
                Spacer()
                Button("生成图表") {
                    onRun(
                        ChartSpec(
                            kind: state.kind,
                            groupColumn: state.groupColumn,
                            value: PivotValue(column: state.measureColumn, aggregate: state.aggregate)
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.groupColumn.isEmpty || state.measureColumn.isEmpty)
            }

            if numericColumns.isEmpty {
                Text("这个文件没有数值列，先加一个计算列再建图。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("超过 12 个分组时只画前 12 个，其余合并成“其他”。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 460)
        .onAppear {
            // 记住上一次的选择；第一次打开时跳过看起来像主键的首列，避免一上手就撞基数保护。
            if state.groupColumn.isEmpty {
                let categoryWords = ["区域", "地区", "城市", "省份", "渠道", "产品", "状态", "类型", "类别", "分类", "等级", "分组"]
                let preferred = columns.first { column in
                    !column.kind.isNumeric && categoryWords.contains { column.displayName.contains($0) }
                }
                let candidate = preferred
                    ?? columns.dropFirst().first(where: { !$0.kind.isNumeric })
                    ?? columns.first
                state.groupColumn = candidate?.name ?? ""
            }
            if state.measureColumn.isEmpty { state.measureColumn = numericColumns.first?.name ?? "" }
        }
    }
}

/// 一键分析的结果：几张图竖排，每张一个固定高度。
public struct AutoAnalysisView: View {
    let charts: [ChartData]
    let onClose: () -> Void

    public init(charts: [ChartData], onClose: @escaping () -> Void) {
        self.charts = charts
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("一键分析")
                    .font(.headline)
                Text("\(charts.count) 张图 · 自动挑了 \(charts.map(\.title).joined(separator: "、"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("返回数据", action: onClose)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(charts, id: \.title) { chart in
                        ChartView(data: chart, compact: true) {}
                            .frame(height: 320)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 图表结果区：四种图都用 Canvas 画，不引第三方图表库。
public struct ChartView: View {
    let data: ChartData
    /// 放在多图列表里时用紧凑模式：不显示“返回数据”，高度交给外层。
    var compact = false
    let onClose: () -> Void

    public init(data: ChartData, compact: Bool = false, onClose: @escaping () -> Void) {
        self.data = data
        self.compact = compact
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(data.title)
                    .font(.headline)
                Text("\(data.groupCount) 组 · \(String(format: "%.2f", data.elapsed)) 秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if data.mergedCount > 0 {
                    Text("其余 \(data.mergedCount) 组合并成“其他”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !compact {
                    Button("返回数据", action: onClose)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if data.isEmpty {
                Text("没有匹配的数据")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Canvas { context, size in
                    switch data.kind {
                    case .bar: drawBars(context: &context, size: size)
                    case .horizontalBar: drawHorizontalBars(context: &context, size: size)
                    case .line: drawLine(context: &context, size: size)
                    case .pie: drawPie(context: &context, size: size)
                    }
                }
                .padding(18)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilitySummary))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
    }

    private var accent: Color { .accentColor }
    private var secondary: Color { .secondary }

    private func value(_ raw: Double) -> String { ChartData.format(raw) }

    /// 图是画出来的，给辅助功能留一句文字摘要。
    private var accessibilitySummary: String {
        let top = data.points.prefix(3)
            .map { "\($0.label) \(ChartData.format($0.value))" }
            .joined(separator: "，")
        return "\(data.title)，共 \(data.points.count) 组。\(top)"
    }

    /// 坐标轴上的数字用万/亿收短，不然十位数会挤出绘图区。
    private func axisLabel(_ raw: Double) -> String {
        let magnitude = Swift.abs(raw)
        if magnitude >= 100_000_000 {
            return String(format: "%.2f亿", raw / 100_000_000)
        }
        if magnitude >= 10_000 {
            return String(format: "%.1f万", raw / 10_000)
        }
        return ChartData.format(raw)
    }

    private func drawBars(context: inout GraphicsContext, size: CGSize) {
        let left: CGFloat = 72
        let bottom: CGFloat = 30
        let plot = CGRect(x: left, y: 18, width: max(10, size.width - left - 16), height: max(10, size.height - bottom - 18))
        let maxValue = max(data.maxValue, 1)

        for step in 0...4 {
            let ratio = CGFloat(step) / 4
            let y = plot.maxY - plot.height * ratio
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
            context.draw(
                Text(axisLabel(maxValue * Double(ratio)))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(secondary),
                at: CGPoint(x: plot.minX - 6, y: y),
                anchor: .trailing
            )
        }

        let count = max(1, data.points.count)
        let gap: CGFloat = 8
        let barWidth = max(4, (plot.width - gap * CGFloat(count + 1)) / CGFloat(count))

        for (index, point) in data.points.enumerated() {
            // “其他”可能远大于单个分组，柱高截到绘图区顶，别画到坐标轴外面。
            let height = min(plot.height, plot.height * CGFloat(point.value / maxValue))
            let x = plot.minX + gap + (barWidth + gap) * CGFloat(index)
            let rect = CGRect(x: x, y: plot.maxY - height, width: barWidth, height: max(1, height))
            context.fill(
                Path(roundedRect: rect, cornerRadius: 3),
                with: .color(accent.opacity(point.label == "其他" ? 0.45 : 0.85))
            )
            // 柱子数量不多时把数值标在柱顶，五个区域差不多高的时候也能读出差距。
            if count <= 8 {
                context.draw(
                    Text(axisLabel(point.value))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(secondary),
                    at: CGPoint(x: rect.midX, y: max(plot.minY, rect.minY - 4)),
                    anchor: .bottom
                )
            }
            context.draw(
                Text(point.label)
                    .font(.system(size: 9))
                    .foregroundStyle(secondary),
                at: CGPoint(x: rect.midX, y: plot.maxY + 12),
                anchor: .top
            )
        }
    }

    private func drawHorizontalBars(context: inout GraphicsContext, size: CGSize) {
        let labelWidth: CGFloat = 110
        let right: CGFloat = 70
        let plot = CGRect(x: 6, y: 10, width: max(10, size.width - labelWidth - right), height: max(10, size.height - 20))
        let maxValue = max(data.maxValue, 1)
        let count = max(1, data.points.count)
        let rowHeight = plot.height / CGFloat(count)

        for (index, point) in data.points.enumerated() {
            let y = plot.minY + rowHeight * CGFloat(index)
            let width = min(plot.width, plot.width * CGFloat(point.value / maxValue))
            let bar = CGRect(x: plot.minX + labelWidth, y: y + rowHeight * 0.18, width: max(1, width), height: rowHeight * 0.64)

            context.draw(
                Text(point.label)
                    .font(.system(size: 10))
                    .foregroundStyle(secondary),
                at: CGPoint(x: plot.minX + labelWidth - 8, y: bar.midY),
                anchor: .trailing
            )
            context.fill(
                Path(roundedRect: bar, cornerRadius: 3),
                with: .color(accent.opacity(point.label == "其他" ? 0.45 : 0.85))
            )
            context.draw(
                Text(axisLabel(point.value))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(secondary),
                at: CGPoint(x: bar.maxX + 6, y: bar.midY),
                anchor: .leading
            )
        }
    }

    private func drawLine(context: inout GraphicsContext, size: CGSize) {
        let left: CGFloat = 72
        let bottom: CGFloat = 30
        let plot = CGRect(x: left, y: 18, width: max(10, size.width - left - 16), height: max(10, size.height - bottom - 18))
        let maxValue = max(data.maxValue, 1)
        let count = data.points.count

        for step in 0...4 {
            let ratio = CGFloat(step) / 4
            let y = plot.maxY - plot.height * ratio
            var path = Path()
            path.move(to: CGPoint(x: plot.minX, y: y))
            path.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(path, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
            context.draw(
                Text(axisLabel(maxValue * Double(ratio)))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(secondary),
                at: CGPoint(x: plot.minX - 6, y: y),
                anchor: .trailing
            )
        }

        func position(_ index: Int) -> CGPoint {
            let ratio = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            let x = plot.minX + plot.width * ratio
            let y = plot.maxY - min(plot.height, plot.height * CGFloat(data.points[index].value / maxValue))
            return CGPoint(x: x, y: y)
        }

        var line = Path()
        for index in 0..<count {
            let point = position(index)
            if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
        }
        context.stroke(line, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

        for index in 0..<count {
            let point = position(index)
            let dot = Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
            context.fill(dot, with: .color(accent))
            if count <= 8 || index % 2 == 0 {
                context.draw(
                    Text(data.points[index].label)
                        .font(.system(size: 9))
                        .foregroundStyle(secondary),
                    at: CGPoint(x: point.x, y: plot.maxY + 12),
                    anchor: .top
                )
            }
        }
    }

    private func drawPie(context: inout GraphicsContext, size: CGSize) {
        let diameter = min(size.width * 0.55, size.height - 20)
        let center = CGPoint(x: diameter / 2 + 12, y: size.height / 2)
        let radius = diameter / 2
        let total = max(data.total, 1)
        var start = Angle.degrees(-90)

        for (index, point) in data.points.enumerated() {
            let fraction = point.value / total
            let end = start + Angle.degrees(360 * fraction)
            var slice = Path()
            slice.move(to: center)
            slice.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
            slice.closeSubpath()
            context.fill(slice, with: .color(accent.opacity(index % 2 == 0 ? 0.85 : 0.6)))
            start = end
        }

        let legendX = center.x + radius + 24
        let lineHeight: CGFloat = min(20, max(12, (size.height - 10) / CGFloat(max(1, data.points.count))))
        for (index, point) in data.points.enumerated() {
            let y = 10 + lineHeight * CGFloat(index) + lineHeight / 2
            let swatch = CGRect(x: legendX, y: y - 4, width: 8, height: 8)
            context.fill(Path(swatch), with: .color(accent.opacity(index % 2 == 0 ? 0.85 : 0.6)))
            let percent = point.value / total * 100
            context.draw(
                Text("\(point.label)  \(String(format: "%.1f", percent))%")
                    .font(.system(size: 10))
                    .foregroundStyle(secondary),
                at: CGPoint(x: swatch.maxX + 6, y: y),
                anchor: .leading
            )
        }
    }
}
