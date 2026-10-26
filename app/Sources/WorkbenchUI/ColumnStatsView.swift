import SwiftUI
import DuckDBKit
import ChartUI

/// 检查器里的统计块。抽成独立的构造器，离屏渲染程序才能把它拉出来量对比度；
/// 返回的是多行视图，放进 List 的 Section 里每行各占一行，跟拆出去之前一致。
public enum ColumnStatsRows {
    @ViewBuilder
    public static func build(_ stats: ColumnStats) -> some View {
        LabeledContent("总行数", value: "\(stats.totalRows)")
        LabeledContent("空值", value: "\(stats.nullCount)（\(String(format: "%.2f", stats.nullRate * 100))%）")
        // 计数一律精确；distinctIsApproximate 保留给以后真需要近似的大表路径。
        LabeledContent(stats.distinctIsApproximate ? "去重值（近似）" : "去重值", value: "\(stats.distinctCount)")
        if let minValue = stats.minValue, let maxValue = stats.maxValue {
            // 文本列的极值是字典序，跟数值的「范围」不是一回事，标签得分开。
            LabeledContent(stats.kind == .text ? "字典序首尾" : "范围", value: "\(minValue) ~ \(maxValue)")
        }
        if let span = stats.timeSpan {
            LabeledContent("时间跨度", value: formatSpan(span))
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
        if let minLength = stats.minLength, let maxLength = stats.maxLength {
            LabeledContent("文本长度", value: "\(minLength) ~ \(maxLength)")
        }
        if let whitespace = stats.whitespaceCount {
            LabeledContent("含首尾空白", value: "\(whitespace) 行")
        }
        if stats.kind == .text, stats.numericCount > 0, stats.conflictCount > 0 {
            conflictRows(stats)
        }
        histogramRows(stats)
        topValueRows(stats)
        timeBucketRows(stats)
    }

    @ViewBuilder
    private static func conflictRows(_ stats: ColumnStats) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("类型冲突")
                .font(.caption)
                .foregroundStyle(.orange)
            // 检查器只有 300 点宽，一句话塞三件事会被截断，拆成两行。
            Text("\(stats.conflictCount) 行不是数字")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(stats.numericCount) 行看着像数字，整列按文本处理")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let sampled = stats.numericSampleRows {
                Text("前 \(sampled) 行抽样，数字行数按比例推算")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(stats.nonNumericExamples, id: \.self) { example in
                Text("反例：\(example)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private static func histogramRows(_ stats: ColumnStats) -> some View {
        if !stats.histogram.isEmpty {
            let maxCount = max(1, stats.histogram.map(\.count).max() ?? 1)
            Text("分布")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(stats.histogram.enumerated()), id: \.offset) { index, bucket in
                    RoundedRectangle(cornerRadius: 1)
                        // 跟图表用同一套推送过的强调色：系统强调色直接画在浅色底上只有 3.97:1。
                        .fill(Color(nsColor: ChartPalette.fill()))
                        .frame(width: 6, height: max(2, 40 * CGFloat(bucket.count) / CGFloat(maxCount)))
                        .help("第 \(index + 1) 格 \(format(bucket.lower)) ~ \(format(bucket.upper))：\(bucket.count) 行")
                }
            }
            .frame(height: 44)
        }
    }

    @ViewBuilder
    private static func topValueRows(_ stats: ColumnStats) -> some View {
        // 时间列下面已经按天列出分布，再把同样的日期当“高频值”列一遍就是重复。
        if !stats.topValues.isEmpty, stats.timeBuckets.isEmpty {
            Text("高频值")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private static func timeBucketRows(_ stats: ColumnStats) -> some View {
        if !stats.timeBuckets.isEmpty {
            Text("按天分布")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(stats.timeBuckets.prefix(10), id: \.self) { bucket in
                HStack {
                    Text(bucket.label).font(.caption)
                    Spacer()
                    Text("\(bucket.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// 时间跨度按天、小时、分钟挑一个合适的粒度，避免出现 5184000 秒这种读不出来的数字。
    public static func formatSpan(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let days = total / 86_400
        if days >= 1 {
            let hours = (total % 86_400) / 3_600
            return hours == 0 ? "\(days) 天" : "\(days) 天 \(hours) 小时"
        }
        let hours = total / 3_600
        if hours >= 1 {
            let minutes = (total % 3_600) / 60
            return minutes == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes) 分"
        }
        let minutes = total / 60
        return minutes >= 1 ? "\(minutes) 分" : "\(total) 秒"
    }
}
