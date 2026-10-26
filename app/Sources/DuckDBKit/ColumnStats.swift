import Foundation

public struct TopValue: Hashable, Sendable {
    public let value: String
    public let count: Int

    public init(value: String, count: Int) {
        self.value = value
        self.count = count
    }
}

public struct HistogramBucket: Hashable, Sendable {
    public let lower: Double
    public let upper: Double
    public let count: Int

    public init(lower: Double, upper: Double, count: Int) {
        self.lower = lower
        self.upper = upper
        self.count = count
    }
}

public struct TimeBucket: Hashable, Sendable {
    public let label: String
    public let count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }
}

public struct ColumnStats: Sendable {
    public let column: String
    public let typeName: String
    public let kind: ColumnKind
    public let totalRows: Int
    public let nullCount: Int
    public let distinctCount: Int
    public let minValue: String?
    public let maxValue: String?
    public let mean: Double?
    public let median: Double?
    public let standardDeviation: Double?
    public let topValues: [TopValue]
    public let histogram: [HistogramBucket]
    public let timeBuckets: [TimeBucket]
    public let numericCount: Int
    public let nonNumericExamples: [String]
    /// 文本列类型冲突的抽样行数。大表不扫全表，这个值非空时界面要标“抽样”。
    public let numericSampleRows: Int?
    public let minLength: Int?
    public let maxLength: Int?
    public let whitespaceCount: Int?
    /// 去重值是不是近似值。大表用 approx_count_distinct 时会标上，界面必须显示“近似”。
    public let distinctIsApproximate: Bool

    public init(
        column: String,
        typeName: String,
        kind: ColumnKind,
        totalRows: Int,
        nullCount: Int,
        distinctCount: Int,
        minValue: String?,
        maxValue: String?,
        mean: Double?,
        median: Double?,
        standardDeviation: Double?,
        topValues: [TopValue] = [],
        histogram: [HistogramBucket] = [],
        timeBuckets: [TimeBucket] = [],
        numericCount: Int = 0,
        nonNumericExamples: [String] = [],
        numericSampleRows: Int? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        whitespaceCount: Int? = nil,
        distinctIsApproximate: Bool = false
    ) {
        self.column = column
        self.typeName = typeName
        self.kind = kind
        self.totalRows = totalRows
        self.nullCount = nullCount
        self.distinctCount = distinctCount
        self.minValue = minValue
        self.maxValue = maxValue
        self.mean = mean
        self.median = median
        self.standardDeviation = standardDeviation
        self.topValues = topValues
        self.histogram = histogram
        self.timeBuckets = timeBuckets
        self.numericCount = numericCount
        self.nonNumericExamples = nonNumericExamples
        self.numericSampleRows = numericSampleRows
        self.minLength = minLength
        self.maxLength = maxLength
        self.whitespaceCount = whitespaceCount
        self.distinctIsApproximate = distinctIsApproximate
    }

    public var conflictCount: Int {
        max(0, totalRows - nullCount - numericCount)
    }

    public var nullRate: Double {
        totalRows == 0 ? 0 : Double(nullCount) / Double(totalRows)
    }

    /// 时间跨度：只在日期或时间列、且最早最晚都能解析时给出秒数。
    public var timeSpan: TimeInterval? {
        guard kind == .date || kind == .timestamp,
              let minValue, let maxValue,
              let lower = ColumnStats.parseTemporal(minValue),
              let upper = ColumnStats.parseTemporal(maxValue) else { return nil }
        return upper.timeIntervalSince(lower)
    }

    /// DuckDB 的日期是 2026-01-01，时间戳是 2026-01-01 10:00:00，两种都认。
    static func parseTemporal(_ text: String) -> Date? {
        let withTime = DateFormatter()
        withTime.locale = Locale(identifier: "en_US_POSIX")
        withTime.timeZone = TimeZone(secondsFromGMT: 0)
        withTime.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = withTime.date(from: text) { return date }
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dayOnly.dateFormat = "yyyy-MM-dd"
        return dayOnly.date(from: String(text.prefix(10)))
    }
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case csv
    case parquet

    public var title: String {
        switch self {
        case .csv: return "CSV"
        case .parquet: return "Parquet"
        }
    }

    public var fileExtension: String { rawValue }
}
