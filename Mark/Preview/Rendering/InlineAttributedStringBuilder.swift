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
        metrics: PreviewMetrics,
        baseFont: Font? = nil
    ) -> AttributedString {
        let resolvedBaseFont = baseFont ?? Font.system(size: metrics.bodyFontSize)
        return content.nodes.reduce(into: AttributedString()) { result, node in
            result.append(
                build(
                    node,
                    theme: theme,
                    metrics: metrics,
                    baseFont: resolvedBaseFont
                )
            )
        }
    }

    private func build(
        _ node: PreviewInlineNode,
        theme: PreviewTheme,
        metrics: PreviewMetrics,
        baseFont: Font
    ) -> AttributedString {
        switch node {
        case .text(let text), .rawText(let text):
            return base(text, theme: theme, font: baseFont)

        case .softBreak:
            return base(" ", theme: theme, font: baseFont)

        case .hardBreak:
            return base("\n", theme: theme, font: baseFont)

        case .code(let code):
            var result = base(code, theme: theme, font: baseFont)
            result.font = Font.system(
                size: metrics.codeFontSize,
                weight: .regular,
                design: .monospaced
            )
            result.backgroundColor = theme.codeTheme.background
            return result

        case .emphasis(let children):
            var result = build(
                children,
                theme: theme,
                metrics: metrics,
                baseFont: baseFont
            )
            result.inlinePresentationIntent = .emphasized
            return result

        case .strong(let children):
            var result = build(
                children,
                theme: theme,
                metrics: metrics,
                baseFont: baseFont
            )
            result.inlinePresentationIntent = .stronglyEmphasized
            return result

        case .strikethrough(let children):
            var result = build(
                children,
                theme: theme,
                metrics: metrics,
                baseFont: baseFont
            )
            result.strikethroughStyle = .single
            return result

        case .link(let destination, _, let children):
            var result = build(
                children,
                theme: theme,
                metrics: metrics,
                baseFont: baseFont
            )
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
                font: baseFont
            )
        }
    }

    private func build(
        _ children: [PreviewInlineNode],
        theme: PreviewTheme,
        metrics: PreviewMetrics,
        baseFont: Font
    ) -> AttributedString {
        children.reduce(into: AttributedString()) { result, child in
            result.append(
                build(
                    child,
                    theme: theme,
                    metrics: metrics,
                    baseFont: baseFont
                )
            )
        }
    }

    private func base(
        _ string: String,
        theme: PreviewTheme,
        font: Font
    ) -> AttributedString {
        var result = AttributedString(string)
        result.foregroundColor = NSColor(theme.primaryText)
        result.font = font
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
