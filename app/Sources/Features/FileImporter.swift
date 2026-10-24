import Foundation
import DuckDBKit

public struct OpenedFile: Sendable {
    public let url: URL
    public let session: QuerySession
    public let encoding: TextEncoding

    public init(url: URL, session: QuerySession, encoding: TextEncoding) {
        self.url = url
        self.session = session
        self.encoding = encoding
    }
}

public enum FileImporter {
    public static let supportedExtensions: Set<String> = ["csv", "tsv", "tab"]

    public static func open(url: URL) throws -> OpenedFile {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw ImportError(
                userMessage: "不支持这个文件格式",
                technicalDetail: "扩展名：\(ext.isEmpty ? "无" : ext)",
                recoverySuggestion: "目前支持 CSV、TSV 和 TAB，其他格式后续版本再说。"
            )
        }

        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw ImportError(
                userMessage: "没有读取这个文件的权限",
                technicalDetail: url.path,
                recoverySuggestion: "到系统设置里给应用授予文件访问权限，或把文件复制到桌面再试。"
            )
        }

        let sample = try EncodingDetector.readSample(of: url)
        let encoding = EncodingDetector.detect(sample: sample)

        if encoding != .utf16LE && encoding != .utf16BE, isLikelyBinary(sample) {
            throw ImportError(
                userMessage: "看起来不是文本文件",
                technicalDetail: "样本里含 NUL 字节或大量控制字符",
                recoverySuggestion: "确认文件没有被改成 .csv 后缀，或者换一个文件试试。"
            )
        }

        let sampleText: String
        switch encoding {
        case .utf8:
            sampleText = String(decoding: sample, as: UTF8.self)
        case .utf8BOM:
            sampleText = String(decoding: sample.dropFirst(3), as: UTF8.self)
        case .gb18030:
            sampleText = String(data: sample, encoding: EncodingDetector.gb18030) ?? ""
        case .utf16LE:
            sampleText = String(data: sample, encoding: .utf16LittleEndian) ?? ""
        case .utf16BE:
            sampleText = String(data: sample, encoding: .utf16BigEndian) ?? ""
        }

        guard !sampleText.isEmpty else {
            throw ImportError(
                userMessage: "看起来不是文本文件",
                technicalDetail: "前 64KB 无法按文本解码",
                recoverySuggestion: "确认文件没有被改成 .csv 后缀，或者换一个文件试试。"
            )
        }

        let format = CSVSniffer.sniff(sample: sampleText, fileExtension: ext)
        let readableURL = try TextFileTranscoder.transcodeIfNeeded(source: url, encoding: encoding)
        let session = try DuckDBSession.open(url: readableURL, format: format)
        return OpenedFile(url: url, session: session, encoding: encoding)
    }

    /// NUL 字节或控制字符比例过高，基本可以判定为二进制文件。
    static func isLikelyBinary(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        if data.contains(0) { return true }
        var control = 0
        for byte in data.prefix(64 * 1024) {
            if byte < 0x09 || (byte > 0x0D && byte < 0x20) || byte == 0x7F {
                control += 1
            }
        }
        return Double(control) / Double(min(data.count, 64 * 1024)) > 0.02
    }
}
