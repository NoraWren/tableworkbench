import Foundation

/// 图表类型。只做单维度的聚合呈现，不做交叉图。
public enum ChartKind: String, CaseIterable, Hashable, Sendable {
    case bar
    case horizontalBar
    case line
    case pie

    public var title: String {
        switch self {
        case .bar: return "柱状图"
        case .horizontalBar: return "条形图"
        case .line: return "折线图"
        case .pie: return "饼图"
        }
    }
}

public struct ChartSpec: Hashable, Sendable {
    public var kind: ChartKind
    public var groupColumn: String
    public var value: PivotValue
    /// 最多画多少个分组，其余合并成“其他”。
    public var limit: Int

    public init(kind: ChartKind, groupColumn: String, value: PivotValue, limit: Int = 12) {
        self.kind = kind
        self.groupColumn = groupColumn
        self.value = value
        self.limit = max(1, limit)
    }

    public var isValid: Bool { !groupColumn.isEmpty }

    /// 图表就是单维度透视：一个分组列，一个度量。
    public var pivotSpec: PivotSpec {
        PivotSpec(rows: [groupColumn], columns: [], values: [value])
    }

    public var title: String {
        "\(groupColumn) · \(value.title)"
    }
}

public struct ChartPoint: Hashable, Sendable {
    public let label: String
    public let value: Double

    public init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

/// 画图需要的全部数据，已经排好序、收口、算好最大值。
public struct ChartData: Sendable {
    public let kind: ChartKind
    public let title: String
    public let points: [ChartPoint]
    public let total: Double
    public let maxValue: Double
    public let elapsed: TimeInterval
    public let groupCount: Int
    public let mergedCount: Int

    public var isEmpty: Bool { points.isEmpty }

    public init(
        kind: ChartKind,
        title: String,
        points: [ChartPoint],
        total: Double,
        maxValue: Double,
        elapsed: TimeInterval,
        groupCount: Int,
        mergedCount: Int = 0
    ) {
        self.kind = kind
        self.title = title
        self.points = points
        self.total = total
        self.maxValue = maxValue
        self.elapsed = elapsed
        self.groupCount = groupCount
        self.mergedCount = mergedCount
    }

    /// 把两列的聚合结果转成图上的点：解析数值、排序、超过上限的合并成“其他”。
    public static func build(result: SQLResult, spec: ChartSpec) -> ChartData {
        var parsed: [(label: String, value: Double)] = []
        parsed.reserveCapacity(result.rows.count)
        for row in result.rows {
            guard row.count >= 2, let rawLabel = row[0], let rawValue = row[1] else { continue }
            guard let value = Double(rawValue), value.isFinite else { continue }
            let label = rawLabel.isEmpty ? "(空白)" : rawLabel
            parsed.append((label, value))
        }

        let sorted: [(label: String, value: Double)]
        switch spec.kind {
        case .line:
            // 折线看的是趋势，按标签升序，日期字符串正好能这么排。
            sorted = parsed.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
        default:
            sorted = parsed.sorted { $0.value > $1.value }
        }

        var points: [ChartPoint] = []
        var mergedCount = 0
        if sorted.count > spec.limit {
            let head = sorted.prefix(spec.limit)
            points = head.map { ChartPoint(label: $0.label, value: $0.value) }
            let rest = sorted.dropFirst(spec.limit)
            mergedCount = rest.count
            let restSum = rest.reduce(0.0) { $0 + $1.value }
            if restSum.isFinite {
                points.append(ChartPoint(label: "其他", value: restSum))
            }
        } else {
            points = sorted.map { ChartPoint(label: $0.label, value: $0.value) }
        }

        let total = points.reduce(0.0) { $0 + $1.value }
        // 量级按前 N 名算，不让“其他”这个合计值把别的柱压扁。
        let named = points.filter { $0.label != "其他" }
        let maxValue = (named.isEmpty ? points : named).map(\.value).max() ?? 0

        return ChartData(
            kind: spec.kind,
            title: spec.title,
            points: points,
            total: total,
            maxValue: maxValue,
            elapsed: result.elapsed,
            groupCount: parsed.count,
            mergedCount: mergedCount
        )
    }
}

public extension ChartData {
    /// 12,345.68 这样的展示格式，超过一万加千分位。
    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}
