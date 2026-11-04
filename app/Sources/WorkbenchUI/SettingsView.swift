import SwiftUI
import AppKit
import DuckDBKit

private final class PrivacyState: ObservableObject {
    @Published var sizeText = "—"

    func refresh() {
        let bytes = ParquetCache.shared.totalSizeBytes()
        sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct SettingsView: View {
    @AppStorage("cacheLimitGB") private var cacheLimitGB = 10
    @AppStorage("defaultExportFormat") private var exportFormat = "csv"
    @AppStorage("copyIncludesHeader") private var copyIncludesHeader = true

    @StateObject private var privacy = PrivacyState()
    public init() {}

    public var body: some View {
        TabView {
            general
                .tabItem { Label("通用", systemImage: "gearshape") }
            privacyTab
                .tabItem { Label("隐私", systemImage: "lock") }
            about
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 320)
        .onAppear {
            applyCacheLimit()
            privacy.refresh()
        }
        .onChange(of: cacheLimitGB) { _, _ in applyCacheLimit() }
    }

    private var general: some View {
        Form {
            Picker("缓存上限", selection: $cacheLimitGB) {
                Text("5 GB").tag(5)
                Text("10 GB").tag(10)
                Text("20 GB").tag(20)
            }
            Picker("默认导出格式", selection: $exportFormat) {
                Text("CSV").tag("csv")
                Text("Parquet").tag("parquet")
            }
            Toggle("复制时包含表头", isOn: $copyIncludesHeader)
        }
        .padding(20)
    }

    private var privacyTab: some View {
        Form {
            LabeledContent("缓存占用", value: privacy.sizeText)
            Button("清除缓存") {
                ParquetCache.shared.clearAll()
                privacy.refresh()
            }
            LabeledContent("网络", value: "AI 未启用，应用不联网")
        }
        .padding(20)
        .onAppear { privacy.refresh() }
    }

    private var about: some View {
        VStack(spacing: 8) {
            Text("本地表格工作台")
                .font(.title3)
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                .font(.callout)
            Text("Apache License 2.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("© 2026 Kong Qi")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("问题反馈：GitHub Issues（发布后启用）")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyCacheLimit() {
        ParquetCache.shared.setLimitBytes(Int64(cacheLimitGB) * 1024 * 1024 * 1024)
    }
}
