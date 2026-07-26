//
//  CodeBlockView.swift
//  DiagramDown
//

import SwiftUI

struct CodeBlockView: View {
    let source: String
    let language: CodeLanguage?
    let rawLanguage: String?
    let theme: PreviewTheme
    let metrics: PreviewMetrics

    @State private var content: AttributedString

    init(
        source: String,
        language: CodeLanguage?,
        rawLanguage: String?,
        theme: PreviewTheme,
        metrics: PreviewMetrics
    ) {
        self.source = source
        self.language = language
        self.rawLanguage = rawLanguage
        self.theme = theme
        self.metrics = metrics
        _content = State(initialValue: AttributedString(source))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = rawLanguage, !label.isEmpty {
                Text(label)
                    .font(.system(size: 10 * metrics.zoom, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, metrics.codeInset)
                    .padding(.top, 7 * metrics.zoom)
            }
            ScrollView(.horizontal) {
                Text(content)
                    .font(
                        .system(
                            size: metrics.codeFontSize,
                            design: .monospaced
                        )
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(metrics.codeInset)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(theme.codeTheme.background))
        .clipShape(RoundedRectangle(cornerRadius: 8 * metrics.zoom))
        .overlay {
            RoundedRectangle(cornerRadius: 8 * metrics.zoom)
                .stroke(theme.border, lineWidth: 1)
        }
        .task(id: requestID) {
            content = await TreeSitterCodeHighlighter.shared.highlight(
                source: source,
                language: language,
                theme: theme.codeTheme
            )
        }
    }

    private var requestID: String {
        [
            MarkdownParserService.digest(source),
            language?.rawValue ?? "plain",
            theme.codeTheme.id,
        ].joined(separator: ":")
    }
}
