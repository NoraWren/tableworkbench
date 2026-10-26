import AppKit

/// 轻量单元格：直接画文本，不用 NSTextField。
/// 宽表滚动时一帧要更新几千个单元格，控件那套布局与校验开销省掉后帧耗时明显下降。
public final class GridTextCellView: NSView {
    private var content: NSAttributedString?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let content else { return }
        let height = content.size().height
        let rect = NSRect(
            x: 6,
            y: max(0, (bounds.height - height) / 2),
            width: max(1, bounds.width - 12),
            height: max(1, height)
        )
        content.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    public func configure(text: String, alignment: NSTextAlignment, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        content = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        toolTip = text
        // 自绘之后 NSTextField 自带的辅助功能文本没了，这里补回来，VoiceOver 才读得到格子内容。
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
        needsDisplay = true
    }
}
