import AppKit
import SwiftUI
import DuckDBKit
import Features
import SQLEditorUI

// 把 SQL 编辑器与补全候选面板离屏渲染成一张 PNG，用来检查外观。
// 用法：TableWorkbenchSQLSnapshot <输出路径>

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/sql-editor.png"

let columns = ["订单编号", "客户名称", "区域", "渠道", "产品", "数量", "单价", "金额", "成本", "毛利", "状态"]
let tables = ["data"]

func renderTextView(text: String) -> NSImage? {
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 720, height: 130))
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 720, height: 130))
    textView.isRichText = false
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.string = text
    scroll.documentView = textView
    scroll.hasVerticalScroller = false
    scroll.drawsBackground = true
    scroll.backgroundColor = .textBackgroundColor
    scroll.layoutSubtreeIfNeeded()
    guard let rep = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds) else { return nil }
    scroll.cacheDisplay(in: scroll.bounds, to: rep)
    let image = NSImage(size: scroll.bounds.size)
    image.addRepresentation(rep)
    return image
}

MainActor.assumeIsolated {
    var storage = "SELECT 区域, SUM(金额) FROM data WHERE 区域 = '华南' GROUP BY 区"
    let binding = Binding(get: { storage }, set: { storage = $0 })
    let coordinator = SQLTextView.Coordinator(text: binding)
    coordinator.columns = columns
    coordinator.tables = tables

    let window = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 760, height: 260),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.title = "SQL"

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 260))
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    window.contentView = container

    let header = NSTextField(labelWithAttributedString: NSAttributedString(
        string: "SQL   只读 · 结果最多 10 万行",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
    ))
    header.frame = NSRect(x: 14, y: 226, width: 400, height: 18)
    container.addSubview(header)

    let editor = NSScrollView(frame: NSRect(x: 14, y: 16, width: 732, height: 130))
    let textView = CompletionTextView(frame: NSRect(x: 0, y: 0, width: 732, height: 130))
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.textContainerInset = NSSize(width: 6, height: 6)
    textView.string = storage
    editor.documentView = textView
    editor.hasVerticalScroller = true
    editor.drawsBackground = true
    editor.backgroundColor = .textBackgroundColor
    container.addSubview(editor)
    container.layoutSubtreeIfNeeded()

    // 光标停在 "区" 后面，触发补全。
    textView.setSelectedRange(NSRange(location: (storage as NSString).length, length: 0))
    textView.completionSource = coordinator
    textView.refreshCompletion()
    print("候选: \(textView.suggestions)")

    // 弹窗单独绘制成一张图，叠在编辑器下方。
    let popup = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let table = NSTableView()
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
    column.width = 240
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 20
    table.backgroundColor = .controlBackgroundColor
    let rows = textView.suggestions.isEmpty ? ["区域", "城市"] : textView.suggestions
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 260, height: CGFloat(min(rows.count, 5)) * 20 + 8))
    scroll.drawsBackground = true
    scroll.backgroundColor = .controlBackgroundColor
    scroll.hasVerticalScroller = false
    popup.contentView = scroll

    // 用一张合成图表示最终外观：编辑器 + 浮在它下方的候选面板。
    let canvasSize = NSSize(width: 760, height: 320)
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    NSColor.windowBackgroundColor.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    if let editorImage = renderTextView(text: storage) {
        editorImage.draw(in: NSRect(x: 14, y: 170, width: 732, height: 130))
    }

    // 候选面板背景与边框。
    let panelRect = NSRect(x: 40, y: 40, width: 260, height: CGFloat(min(rows.count, 5)) * 20 + 8)
    NSColor.controlBackgroundColor.setFill()
    panelRect.fill()
    NSColor.separatorColor.setStroke()
    let border = NSBezierPath(roundedRect: panelRect, xRadius: 6, yRadius: 6)
    border.lineWidth = 1
    border.stroke()

    let itemAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
        .foregroundColor: NSColor.labelColor
    ]
    let selectedAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
        .foregroundColor: NSColor.labelColor
    ]
    for (index, item) in rows.prefix(5).enumerated() {
        let rowRect = NSRect(x: panelRect.minX, y: panelRect.maxY - CGFloat(index + 1) * 20 - 4, width: panelRect.width, height: 20)
        if index == 0 {
            NSColor.selectedContentBackgroundColor.setFill()
            rowRect.insetBy(dx: 4, dy: 1).fill()
        }
        (item as NSString).draw(
            at: NSPoint(x: rowRect.minX + 10, y: rowRect.minY + 4),
            withAttributes: index == 0 ? selectedAttributes : itemAttributes
        )
    }
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("渲染失败\n".utf8))
        exit(1)
    }
    try? png.write(to: URL(fileURLWithPath: output))
    print(output)
}

