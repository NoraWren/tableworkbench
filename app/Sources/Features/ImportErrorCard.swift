import SwiftUI
import DuckDBKit

private final class ErrorCardState: ObservableObject {
    @Published var showDetail = false
}

public struct ImportErrorCard: View {
    public let error: ImportError
    public let onDismiss: () -> Void
    @StateObject private var state = ErrorCardState()

    public init(error: ImportError, onDismiss: @escaping () -> Void) {
        self.error = error
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error.userMessage)
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭错误提示")
            }

            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let detail = error.technicalDetail, !detail.isEmpty {
                // 自己拼展开行：DisclosureGroup 只认小箭头那一小块，点"查看技术细节"这几个字没反应。
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        state.showDetail.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.showDetail ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                            Text("查看技术细节")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.showDetail ? "收起技术细节" : "查看技术细节")

                    if state.showDetail {
                        // 短报错按内容高度显示；超过 8 行才换成滚动，别把卡片顶出窗口。
                        let lines = detail.split(separator: "\n", omittingEmptySubsequences: false).count
                        if lines > 8 {
                            ScrollView { detailText(detail) }
                                .frame(height: 120)
                        } else {
                            detailText(detail)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.35)))
        .shadow(radius: 8, y: 2)
        .padding()
    }

    private func detailText(_ detail: String) -> some View {
        Text(detail)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
