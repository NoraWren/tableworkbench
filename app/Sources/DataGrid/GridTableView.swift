import AppKit

public final class GridTableView: NSTableView {
    /// 双击行时回传行号，由外层决定怎么展示。
    public var onRowActivate: ((Int) -> Void)?

    @objc public func activateRow(_ sender: Any?) {
        let row = clickedRow
        guard row >= 0 else { return }
        onRowActivate?(row)
    }

    @objc public func copy(_ sender: Any?) {
        guard let source = dataSource as? GridDataSource else { return }
        let rows = selectedRowIndexes
        guard !rows.isEmpty else { return }

        let includeHeader = UserDefaults.standard.object(forKey: "copyIncludesHeader") as? Bool ?? true

        // 一次复制太多行会卡住界面，先问一句。
        if rows.count > 10_000 {
            let alert = NSAlert()
            alert.messageText = "复制 \(rows.count) 行？"
            alert.informativeText = "行数较多，生成 TSV 需要一点时间，界面会短暂停顿。"
            alert.addButton(withTitle: "复制")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let text = source.tsv(for: rows, includeHeader: includeHeader)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
