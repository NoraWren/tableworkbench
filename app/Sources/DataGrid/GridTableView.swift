import AppKit

public final class GridTableView: NSTableView {
    /// 双击行时回传行号，由外层决定怎么展示。
    public var onRowActivate: ((Int) -> Void)?

    /// 大范围复制的确认动作，默认弹系统对话框。测试里换成直接返回 true/false。
    public var confirmCopy: ((Int) -> Bool)?

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
        if CopyConfirmation.needsConfirmation(rowCount: rows.count) {
            let accepted: Bool
            if let confirmCopy {
                accepted = confirmCopy(rows.count)
            } else {
                let alert = NSAlert()
                alert.messageText = CopyConfirmation.title(rowCount: rows.count)
                alert.informativeText = CopyConfirmation.message
                alert.addButton(withTitle: "复制")
                alert.addButton(withTitle: "取消")
                accepted = alert.runModal() == .alertFirstButtonReturn
            }
            guard accepted else { return }
        }

        let text = source.tsv(for: rows, includeHeader: includeHeader)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
