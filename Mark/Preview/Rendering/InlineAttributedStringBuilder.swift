//
//  InlineAttributedStringBuilder.swift
//  DiagramDown
//

import AppKit
import Foundation
import SwiftUI

struct InlineAttributedStringBuilder {
    func build(
        _ content: PreviewInlineContent,
        theme: PreviewTheme,
        metrics: PreviewMetrics
    ) -> AttributedString {
        content.nodes.reduce(into: AttributedString()) { result, node in
            result.append(build(node, theme: theme, metrics: metrics))
        }
    }

    private func build(
        _ node: PreviewInlineNode,
        theme: PreviewTheme,
        metrics: PreviewMetrics
    ) -> AttributedString {
        switch node {
        case .text(let text), .rawText(let text):
            return base(text, theme: theme, metrics: metrics)

        case .softBreak:
            return base(" ", theme: theme, metrics: metrics)

        case .hardBreak:
            return base("\n", theme: theme, metrics: metrics)

        case .code(let code):
            var result = base(code, theme: theme, metrics: metrics)
            result.font = Font.system(
                size: metrics.codeFontSize,
                weight: .regular,
                design: .monospaced
            )
            result.backgroundColor = theme.codeTheme.background
            return result

        case .emphasis(let children):
            var result = build(children, theme: theme, metrics: metrics)
            result.inlinePresentationIntent = .emphasized
            return result

        case .strong(let children):
            var result = build(children, theme: theme, metrics: metrics)
            result.inlinePresentationIntent = .stronglyEmphasized
            return result

        case .strikethrough(let children):
            var result = build(children, theme: theme, metrics: metrics)
            result.strikethroughStyle = .single
            return result

        case .link(let destination, _, let children):
            var result = build(children, theme: theme, metrics: metrics)
            if let url = SafePreviewURL.link(destination) {
                result.link = url
                result.foregroundColor = NSColor(theme.accent)
                result.underlineStyle = .single
            }
            return result

        case .image(_, _, let alt):
            return base(
                alt.isEmpty ? "[Image]" : "[Image: \(alt)]",
                theme: theme,
                metrics: metrics
            )
        }
    }

    private func build(
        _ children: [PreviewInlineNode],
        theme: PreviewTheme,
        metrics: PreviewMetrics
    ) -> AttributedString {
        children.reduce(into: AttributedString()) { result, child in
            result.append(build(child, theme: theme, metrics: metrics))
        }
    }

    private func base(
        _ string: String,
        theme: PreviewTheme,
        metrics: PreviewMetrics
    ) -> AttributedString {
        var result = AttributedString(string)
        result.foregroundColor = NSColor(theme.primaryText)
        result.font = Font.system(size: metrics.bodyFontSize)
        return result
    }
}

enum SafePreviewURL {
    static func link(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else {
            return nil
        }
        return url
    }
}
