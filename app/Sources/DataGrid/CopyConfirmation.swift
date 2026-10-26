import Foundation

/// 大范围复制的确认规则，抽成纯函数便于断言（R-EXP-04）。
public enum CopyConfirmation {
    /// 超过这个行数才打扰用户。
    public static let threshold = 10_000

    public static func needsConfirmation(rowCount: Int) -> Bool {
        rowCount > threshold
    }

    public static func title(rowCount: Int) -> String {
        "复制 \(rowCount) 行？"
    }

    public static let message = "行数较多，生成 TSV 需要一点时间，界面会短暂停顿。"
}
