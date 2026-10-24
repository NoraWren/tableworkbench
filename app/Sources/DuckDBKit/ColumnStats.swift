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
    public let minLength: Int?
    public let maxLength: Int?
    public let whitespaceCount: Int?

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
        minLength: Int? = nil,
        maxLength: Int? = nil,
        whitespaceCount: Int? = nil
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
        self.minLength = minLength
        self.maxLength = maxLength
        self.whitespaceCount = whitespaceCount
    }

    public var conflictCount: Int {
        max(0, totalRows - nullCount - numericCount)
    }

    public var nullRate: Double {
        totalRows == 0 ? 0 : Double(nullCount) / Double(totalRows)
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
