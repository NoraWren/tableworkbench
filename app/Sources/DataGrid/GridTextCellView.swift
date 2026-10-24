import AppKit

/// 轻量单元格：直接画文本，不用 NSTextField。
/// 宽表滚动时一帧要更新几千个单元格，控件那套布局与校验开销省掉后帧耗时明显下降。
final class GridTextCellView: NSView {
    private var content: NSAttributedString?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
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

    func configure(text: String, alignment: NSTextAlignment, color: NSColor) {
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
        needsDisplay = true
    }
}
