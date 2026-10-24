import Foundation
import CoreXLSX
import ZIPFoundation

public struct XLSXSheetInfo: Sendable {
    public let name: String
    public let path: String
}

public enum XLSXConverter {
    public static let maxCells = 1_000_000

    public static func sheets(at url: URL) throws -> [XLSXSheetInfo] {
        guard let file = XLSXFile(filepath: url.path) else {
            throw ImportError(
                userMessage: "无法解析这个 Excel 文件",
                technicalDetail: "XLSXFile 初始化失败",
                recoverySuggestion: "确认文件是有效的 .xlsx，必要时用 Excel 另存一份。"
            )
        }
        guard let workbook = try file.parseWorkbooks().first else {
            throw ImportError(userMessage: "工作簿里没有工作表", technicalDetail: nil, recoverySuggestion: "检查文件内容。")
        }
        let entries = try file.parseWorksheetPathsAndNames(workbook: workbook)
        return entries.enumerated().map { index, entry in
            XLSXSheetInfo(name: entry.name ?? "Sheet\(index + 1)", path: entry.path)
        }
    }

    /// 流式解析选中的工作表，逐行写成 UTF-8 CSV，返回实际使用的工作表名。
    public static func convert(url: URL, sheetName: String?, destination: URL) throws -> String {
        let sheets = try sheets(at: url)
        guard let selected = sheetName.flatMap({ name in sheets.first { $0.name == name } }) ?? sheets.first else {
            throw ImportError(userMessage: "工作簿里没有工作表", technicalDetail: nil, recoverySuggestion: "检查文件内容。")
        }
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ImportError(
                userMessage: "无法打开这个 Excel 文件",
                technicalDetail: "zip 容器读取失败",
                recoverySuggestion: "确认文件没有损坏。"
            )
        }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tableworkbench-xlsx-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        var sharedStrings: [String] = []
        if let entry = archive["xl/sharedStrings.xml"] {
            let sharedURL = workingDirectory.appendingPathComponent("sharedStrings.xml")
            try archive.extract(entry, to: sharedURL)
            sharedStrings = try parseSharedStrings(at: sharedURL)
        }

        let entryPath = selected.path.hasPrefix("/") ? String(selected.path.dropFirst()) : selected.path
        guard let sheetEntry = archive[entryPath] else {
            throw ImportError(
                userMessage: "找不到工作表内容",
                technicalDetail: selected.path,
                recoverySuggestion: "重新用 Excel 保存一次。"
            )
        }
        let sheetURL = workingDirectory.appendingPathComponent("sheet.xml")
        try archive.extract(sheetEntry, to: sheetURL)

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        let writer = SheetWriter(handle: handle, sharedStrings: sharedStrings)
        defer { try? handle.close() }

        guard let parser = XMLParser(contentsOf: sheetURL) else {
            throw ImportError(userMessage: "无法读取工作表", technicalDetail: nil, recoverySuggestion: "重新保存文件。")
        }
        parser.delegate = writer
        parser.shouldProcessNamespaces = false
        let parsed = parser.parse()
        writer.finish()

        if let failure = writer.failure { throw failure }
        guard parsed else {
            throw ImportError(
                userMessage: "解析工作表失败",
                technicalDetail: parser.parserError?.localizedDescription,
                recoverySuggestion: "确认文件没有损坏。"
            )
        }
        try handle.close()
        return selected.name
    }

    private static func parseSharedStrings(at url: URL) throws -> [String] {
        guard let parser = XMLParser(contentsOf: url) else { return [] }
        let delegate = SharedStringsParser()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.items
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var items: [String] = []
    private var current = ""
    private var inText = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "si" {
            current = ""
        } else if elementName == "t" {
            inText = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "t" {
            inText = false
        } else if elementName == "si" {
            items.append(current)
        }
    }
}

private final class SheetWriter: NSObject, XMLParserDelegate {
    let handle: FileHandle
    let sharedStrings: [String]
    var failure: Error?

    private var buffer = ""
    private var expectedColumns = 0
    private var maxColumn = 0
    private var headerWritten = false
    private var dataRows = 0
    private var currentRow: [Int: String] = [:]
    private var currentColumn: Int?
    private var currentType: String?
    private var valueBuffer = ""
    private var inlineBuffer = ""
    private var inValue = false
    private var inText = false
    private var inInline = false

    init(handle: FileHandle, sharedStrings: [String]) {
        self.handle = handle
        self.sharedStrings = sharedStrings
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "dimension":
            if let reference = attributeDict["ref"], let end = reference.split(separator: ":").last {
                expectedColumns = max(expectedColumns, columnIndex(String(end)))
            }
        case "row":
            currentRow = [:]
        case "c":
            currentColumn = attributeDict["r"].map(columnIndex)
            currentType = attributeDict["t"]
            valueBuffer = ""
            inlineBuffer = ""
        case "v":
            inValue = true
        case "is":
            inInline = true
        case "t":
            inText = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { valueBuffer += string }
        if inInline && inText { inlineBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "v":
            inValue = false
        case "t":
            inText = false
        case "is":
            inInline = false
        case "c":
            if let column = currentColumn, let text = cellText() {
                currentRow[column] = text
            }
            currentColumn = nil
        case "row":
            finishRow()
        default:
            break
        }
    }

    func finish() {
        guard !buffer.isEmpty else { return }
        try? handle.write(contentsOf: Data(buffer.utf8))
        buffer.removeAll(keepingCapacity: true)
    }

    private func cellText() -> String? {
        if currentType == "inlineStr" {
            return inlineBuffer.isEmpty ? nil : inlineBuffer
        }
        if currentType == "s" {
            guard let index = Int(valueBuffer), index >= 0, index < sharedStrings.count else { return nil }
            return sharedStrings[index]
        }
        if currentType == "b" {
            if valueBuffer == "1" { return "TRUE" }
            if valueBuffer == "0" { return "FALSE" }
            return nil
        }
        return valueBuffer.isEmpty ? nil : valueBuffer
    }

    private func finishRow() {
        let rowColumns = max(expectedColumns, (currentRow.keys.max() ?? -1) + 1)
        maxColumn = max(maxColumn, rowColumns)
        guard rowColumns > 0 else { return }

        var fields = Array(repeating: "", count: max(maxColumn, rowColumns))
        for (column, value) in currentRow where column < fields.count {
            fields[column] = value
        }

        if !headerWritten {
            for index in fields.indices where fields[index].isEmpty {
                fields[index] = "column_\(index + 1)"
            }
            buffer += fields.map(Self.csvField).joined(separator: ",") + "\n"
            headerWritten = true
        } else {
            buffer += fields.map(Self.csvField).joined(separator: ",") + "\n"
            dataRows += 1
        }

        if dataRows > 0 && (dataRows + 1) * maxColumn > XLSXConverter.maxCells {
            failure = ImportError(
                userMessage: "这张表太大了",
                technicalDetail: "超过 \(XLSXConverter.maxCells) 个单元格",
                recoverySuggestion: "先在 Excel 里裁剪数据，或拆分后再导入。"
            )
            return
        }

        if dataRows % 1000 == 0, !buffer.isEmpty {
            try? handle.write(contentsOf: Data(buffer.utf8))
            buffer.removeAll(keepingCapacity: true)
        }
    }

    private func columnIndex(_ reference: String) -> Int {
        var result = 0
        for scalar in reference.uppercased().unicodeScalars {
            let value = scalar.value
            if value >= 65 && value <= 90 {
                result = result * 26 + Int(value - 64)
            } else if value >= 48 && value <= 57 {
                break
            }
        }
        return max(0, result - 1)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
