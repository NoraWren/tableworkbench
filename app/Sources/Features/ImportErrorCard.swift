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
                DisclosureGroup("查看技术细节", isExpanded: $state.showDetail) {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.35)))
        .shadow(radius: 8, y: 2)
        .padding()
    }
}
