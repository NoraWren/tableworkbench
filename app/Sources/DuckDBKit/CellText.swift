import Foundation

/// 单元格显示用的文本转换。
///
/// 取数时所有列都被 CAST 成 VARCHAR，DOUBLE 的累加值会带上浮点噪声，
/// 求和 1418753.5 在界面上写成 1418753.5000000002。这里只做显示层的收尾，
/// 落盘和导出前的原始值不做改动，判断依据是“舍掉的部分小于自身量级的十亿分之一”，
/// 所以真正的十六位小数不会被误伤。
public enum CellText {
    /// 显示时最多保留几位小数。金额、占比这些都够用，又足够吃掉双精度的尾巴。
    public static let maxFractionDigits = 6

    public static func display(_ text: String, kind: ColumnKind) -> String {
        guard kind == .double else { return text }
        return shortenDouble(text)
    }

    /// 把 1418753.5000000002 收成 1418753.5。只有能被安全收掉时才动，否则原样返回。
    public static func shortenDouble(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // 指数写法、千分位、NULL 这类都别碰。
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "eE")) == nil,
              let value = Double(trimmed),
              value.isFinite else { return text }
        // 极大和极小的数，定长小数写法会变得没法读，保持原样。
        guard abs(value) < 1e15, abs(value) >= 1e-6 || value == 0 else { return text }

        var fixed = String(format: "%.\(maxFractionDigits)f", value)
        if fixed.contains(".") {
            while fixed.hasSuffix("0") { fixed.removeLast() }
            if fixed.hasSuffix(".") { fixed.removeLast() }
        }
        guard let rounded = Double(fixed) else { return text }
        // 只有差异在噪声级别时才替换，避免把用户真有的精度抹掉。
        let tolerance = max(1, abs(value)) * 1e-9
        guard abs(rounded - value) <= tolerance else { return text }
        return fixed == "-0" ? "0" : fixed
    }
}
