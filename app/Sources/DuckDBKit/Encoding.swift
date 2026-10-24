import Foundation
import CoreFoundation

public enum TextEncoding: String, Sendable {
    case utf8 = "UTF-8"
    case utf8BOM = "UTF-8 (BOM)"
    case gb18030 = "GB18030"
    case utf16LE = "UTF-16LE"
    case utf16BE = "UTF-16BE"
    /// Parquet 是二进制列式格式，没有文本编码；用它表示"直接读，不转码"。
    case parquet = "Parquet"

    public var displayName: String { rawValue }

    public var requiresTranscode: Bool { self != .utf8 }
}

public enum EncodingDetector {
    /// 从文件头部样本判断编码。样本末尾可能截断多字节字符，先按 0 到 3 字节回退再判定。
    public static func detect(sample: Data) -> TextEncoding {
        if sample.isEmpty { return .utf8 }
        if sample.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8BOM }
        if sample.starts(with: [0xFF, 0xFE]) { return .utf16LE }
        if sample.starts(with: [0xFE, 0xFF]) { return .utf16BE }

        for trim in 0...3 where sample.count > trim {
            let slice = sample.dropLast(trim)
            if String(data: Data(slice), encoding: .utf8) != nil {
                return .utf8
            }
        }
        return .gb18030
    }

    public static func readSample(of url: URL, byteCount: Int = 64 * 1024) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: byteCount) ?? Data()
    }

    public static var gb18030: String.Encoding {
        let cf = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        return String.Encoding(rawValue: cf)
    }
}

public enum TextFileTranscoder {
    /// 把源文件转成 UTF-8 临时文件。已经是 UTF-8 时直接返回源文件。
    public static func transcodeIfNeeded(source: URL, encoding: TextEncoding) throws -> URL {
        guard encoding.requiresTranscode else { return source }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("tableworkbench-\(UUID().uuidString).utf8.csv")
        try transcode(source: source, encoding: encoding, destination: destination)
        return destination
    }

    public static func transcode(source: URL, encoding: TextEncoding, destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        switch encoding {
        case .parquet:
            throw ImportError(
                userMessage: "Parquet 不需要转码",
                technicalDetail: "Parquet 走列式读取，不经过文本转码",
                recoverySuggestion: "直接打开 Parquet 文件。"
            )
        case .utf8:
            try fileManager.copyItem(at: source, to: destination)
        case .utf8BOM:
            var data = try Data(contentsOf: source)
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
            try data.write(to: destination)
        case .utf16LE, .utf16BE:
            let nsEncoding: String.Encoding = encoding == .utf16LE ? .utf16LittleEndian : .utf16BigEndian
            let text = try String(contentsOf: source, encoding: nsEncoding)
            try text.write(to: destination, atomically: true, encoding: .utf8)
        case .gb18030:
            let data = try Data(contentsOf: source, options: .mappedIfSafe)
            guard let text = String(data: data, encoding: EncodingDetector.gb18030) else {
                throw ImportError(
                    userMessage: "无法按 GB18030 解码这个文件",
                    technicalDetail: "文件不是合法的 GB18030 文本",
                    recoverySuggestion: "用文本编辑器另存为 UTF-8 后重试。"
                )
            }
            try text.write(to: destination, atomically: true, encoding: .utf8)
        }
    }
}
