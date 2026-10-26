import Foundation
import DuckDBKit

/// 结果区顶部那行状态文字。抽成纯函数，测试才能断言两种边界提示。
public struct SQLResultStatus: Equatable, Sendable {
    public let headline: String
    public let summary: String
    /// 截断时提示只显示前多少行，不截断就是 nil。
    public let truncationNotice: String?
    public let isEmpty: Bool

    public static let truncationLimit = 100_000

    public init(headline: String, summary: String, truncationNotice: String?, isEmpty: Bool) {
        self.headline = headline
        self.summary = summary
        self.truncationNotice = truncationNotice
        self.isEmpty = isEmpty
    }

    public init(result: SQLResult, title: String) {
        self.headline = title
        self.summary = "\(Self.grouped(result.rowCount)) 行 · \(String(format: "%.2f", result.elapsed)) 秒"
        self.truncationNotice = result.truncated
            ? "只显示前 \(Self.grouped(Self.truncationLimit)) 行"
            : nil
        self.isEmpty = result.rowCount == 0
    }

    /// 空结果那一大块中间的字。
    public var emptyPlaceholder: String? {
        isEmpty ? "0 行" : nil
    }

    /// 五位数以上加千分位，十万行写成 100,000，扫一眼就知道量级。
    /// 用固定的分隔符，别跟着系统区域设置变，截图和测试才对得上。
    public static func grouped(_ value: Int) -> String {
        let text = String(value)
        guard value >= 1000 else { return text }
        var result = ""
        for (offset, character) in text.enumerated() {
            if offset > 0, (text.count - offset) % 3 == 0 {
                result.append(",")
            }
            result.append(character)
        }
        return result
    }
}
