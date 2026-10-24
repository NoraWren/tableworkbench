import AppKit
import SwiftUI
import DuckDBKit
import ChartUI

// 把一键分析的结果页离屏渲染成 PNG，用来在没有界面自动化时检查排版。
// 用法：TableWorkbenchSnapshot <输出路径>

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/auto-analysis.png"

func chart(_ title: String, _ points: [(String, Double)], kind: ChartKind = .bar) -> ChartData {
    let values = points.map { ChartPoint(label: $0.0, value: $0.1) }
    return ChartData(
        kind: kind,
        title: title,
        points: values,
        total: values.reduce(0) { $0 + $1.value },
        maxValue: values.map(\.value).max() ?? 0,
        elapsed: 0.42,
        groupCount: values.count,
        mergedCount: 0
    )
}

let charts = [
    chart("区域 · 金额 求和", [("华南", 40_930_606.0), ("华中", 40_846_936.0), ("华东", 40_829_504.0), ("西南", 40_804_925.0), ("华北", 40_777_861.0)]),
    chart("产品 · 金额 求和", [("专业版", 40_919_756.0), ("培训", 40_881_383.0), ("实施服务", 40_845_525.0), ("旗舰版", 40_801_120.0), ("标准版", 40_742_038.0)]),
    chart("渠道 · 金额 求和", [("渠道", 51_120_000.0), ("线上", 50_980_000.0), ("直销", 50_870_000.0), ("续约", 50_214_000.0)])
]

let png: Data? = MainActor.assumeIsolated {
    // ImageRenderer 不绘制 ScrollView 与 Button，这里渲染的是列表内容本身。
    let view = VStack(spacing: 14) {
        ForEach(charts, id: \.title) { chart in
            ChartView(data: chart, compact: true) {}
                .frame(height: 300)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    .padding(14)
    .frame(width: 1000)
    .background(Color(nsColor: .windowBackgroundColor))
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

guard let png else {
    FileHandle.standardError.write(Data("渲染失败\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
print(output)
