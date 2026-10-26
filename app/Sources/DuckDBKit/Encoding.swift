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
            try copySkippingBOM(from: source, to: destination)
        case .utf16LE, .utf16BE:
            let nsEncoding: String.Encoding = encoding == .utf16LE ? .utf16LittleEndian : .utf16BigEndian
            try transcodeInChunks(source: source, destination: destination, nsEncoding: nsEncoding, wide: true)
        case .gb18030:
            try transcodeInChunks(source: source, destination: destination, nsEncoding: EncodingDetector.gb18030, wide: false)
        }
    }

    /// 分块转码：一次只读 4MB，处理不了的半个字符留到下一块。
    /// 之前整文件读进内存，GBK 的 500MB 文件峰值能到 1GB 以上。
    private static let chunkSize = 4 * 1024 * 1024

    private static func copySkippingBOM(from source: URL, to destination: URL) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }
        var first = true
        while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
            var chunk = data
            if first {
                if chunk.starts(with: [0xEF, 0xBB, 0xBF]) { chunk.removeFirst(3) }
                first = false
            }
            try output.write(contentsOf: chunk)
        }
    }

    private static func transcodeInChunks(
        source: URL,
        destination: URL,
        nsEncoding: String.Encoding,
        wide: Bool
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        var carry = Data()
        while let data = try input.read(upToCount: chunkSize), !data.isEmpty {
            var buffer = carry
            buffer.append(data)
            let cut = wide ? wideSafeCut(buffer, littleEndian: nsEncoding == .utf16LittleEndian) : textSafeCut(buffer)
            let head = Data(buffer.prefix(cut))
            carry = Data(buffer.dropFirst(cut))
            if !head.isEmpty {
                guard let text = String(data: head, encoding: nsEncoding) else {
                    throw ImportError(
                        userMessage: "无法按 \(nsEncoding) 解码这个文件",
                        technicalDetail: "偏移约 \(buffer.count - cut) 字节处解码失败",
                        recoverySuggestion: "用文本编辑器另存为 UTF-8 后重试。"
                    )
                }
                try output.write(contentsOf: Data(text.utf8))
            }
        }
        if !carry.isEmpty {
            guard let text = String(data: carry, encoding: nsEncoding) else {
                throw ImportError(
                    userMessage: "无法按 \(nsEncoding) 解码这个文件",
                    technicalDetail: "文件末尾残留 \(carry.count) 字节无法解码",
                    recoverySuggestion: "用文本编辑器另存为 UTF-8 后重试。"
                )
            }
            try output.write(contentsOf: Data(text.utf8))
        }
    }

    /// GB18030 的字符是 1、2 或 4 字节。从头按规则扫一遍，返回最后一个完整字符的结尾。
    /// 用解码试探判断边界不可靠：系统解码器遇到半个字符会给出替换字符而不报错。
    /// 优先按换行切块：0x0A 不会出现在多字节字符中间，切在换行后一定是合法边界。
    /// 一整块都没有换行时退回按字节规则扫描。
    static func textSafeCut(_ bytes: Data) -> Int {
        if let newline = bytes.lastIndex(of: 0x0A) {
            return bytes.distance(from: bytes.startIndex, to: newline) + 1
        }
        return gb18030SafePrefixLength(bytes)
    }

    /// 宽字符同理，找最后一个完整的换行码元。
    static func wideSafeCut(_ bytes: Data, littleEndian: Bool) -> Int {
        let buffer = [UInt8](bytes)
        var cut = 0
        var index = 0
        while index + 1 < buffer.count {
            let unit: UInt16 = littleEndian
                ? UInt16(buffer[index]) | (UInt16(buffer[index + 1]) << 8)
                : (UInt16(buffer[index]) << 8) | UInt16(buffer[index + 1])
            if unit == 0x000A { cut = index + 2 }
            index += 2
        }
        return cut > 0 ? cut : utf16SafePrefixLength(bytes)
    }

    public static func gb18030SafePrefixLength(_ bytes: Data) -> Int {
        guard !bytes.isEmpty else { return 0 }
        let buffer = [UInt8](bytes)
        let count = buffer.count
        var index = 0
        while index < count {
            let first = buffer[index]
            if first < 0x80 {
                index += 1
                continue
            }
            if index + 1 >= count {
                return index
            }
            let second = buffer[index + 1]
            if second >= 0x30 && second <= 0x39 {
                if index + 3 >= count {
                    return index
                }
                index += 4
            } else if second >= 0x40 && second <= 0xFE && second != 0x7F {
                index += 2
            } else {
                // 非法字节，交给解码器报错，这里不吞掉。
                index += 1
            }
        }
        return count
    }

    /// UTF-16 每字符 2 或 4 字节；末尾半个字节或孤立的高代理留到下一块。
    public static func utf16SafePrefixLength(_ bytes: Data) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var cut = bytes.count - (bytes.count % 2)
        guard cut >= 2 else { return 0 }
        let start = bytes.startIndex
        let a = bytes[start + cut - 2]
        let b = bytes[start + cut - 1]
        let unit = UInt16(a) | (UInt16(b) << 8)
        let swapped = UInt16(b) | (UInt16(a) << 8)
        let high = (unit >= 0xD800 && unit <= 0xDBFF) || (swapped >= 0xD800 && swapped <= 0xDBFF)
        if high { cut -= 2 }
        return cut
    }
}
