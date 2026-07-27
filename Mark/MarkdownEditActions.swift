//
//  MarkdownEditActions.swift
//  DiagramDown
//

import Foundation

nonisolated enum MarkdownEditAction: String, CaseIterable, Sendable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    case heading
    case blockQuote
    case unorderedList
    case orderedList
    case taskList
    case codeBlock
    case table
    case horizontalRule
}

nonisolated struct MarkdownEditResult: Equatable, Sendable {
    let text: String
    let selection: NSRange
}

nonisolated enum MarkdownEditTransformer {
    static func apply(
        _ action: MarkdownEditAction,
        to source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        let nsSource = source as NSString
        let safeSelection = selection.clamped(to: nsSource.length)

        switch action {
        case .bold:
            return wrap("**", "**", placeholder: "bold text", source, safeSelection)
        case .italic:
            return wrap("_", "_", placeholder: "italic text", source, safeSelection)
        case .strikethrough:
            return wrap("~~", "~~", placeholder: "strikethrough", source, safeSelection)
        case .inlineCode:
            return wrap("`", "`", placeholder: "code", source, safeSelection)
        case .link:
            let selected = nsSource.substring(with: safeSelection)
            let label = selected.isEmpty ? "link text" : selected
            let replacement = "[\(label)](https://)"
            let result = replacing(source, range: safeSelection, with: replacement)
            let urlOffset = 1 + (label as NSString).length + 2
            return MarkdownEditResult(
                text: result,
                selection: NSRange(
                    location: safeSelection.location + urlOffset,
                    length: 8
                )
            )
        case .heading:
            return prefixLines("# ", source: source, selection: safeSelection)
        case .blockQuote:
            return prefixLines("> ", source: source, selection: safeSelection)
        case .unorderedList:
            return prefixLines("- ", source: source, selection: safeSelection)
        case .orderedList:
            return prefixLines("1. ", source: source, selection: safeSelection)
        case .taskList:
            return prefixLines("- [ ] ", source: source, selection: safeSelection)
        case .codeBlock:
            return wrap(
                "```\n",
                "\n```",
                placeholder: "code",
                source,
                safeSelection
            )
        case .table:
            return insertBlock(
                """
                | Column 1 | Column 2 |
                | --- | --- |
                | Value 1 | Value 2 |
                """,
                source: source,
                selection: safeSelection
            )
        case .horizontalRule:
            return insertBlock("---", source: source, selection: safeSelection)
        }
    }

    static func insertImage(
        _ markdown: String,
        source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        let safeSelection = selection.clamped(to: (source as NSString).length)
        return insertBlock(markdown, source: source, selection: safeSelection)
    }

    private static func wrap(
        _ prefix: String,
        _ suffix: String,
        placeholder: String,
        _ source: String,
        _ selection: NSRange
    ) -> MarkdownEditResult {
        let selected = (source as NSString).substring(with: selection)
        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        return MarkdownEditResult(
            text: replacing(source, range: selection, with: replacement),
            selection: NSRange(
                location: selection.location + (prefix as NSString).length,
                length: (content as NSString).length
            )
        )
    }

    private static func prefixLines(
        _ prefix: String,
        source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        let nsSource = source as NSString
        let lineRange = nsSource.lineRange(for: selection)
        let original = nsSource.substring(with: lineRange)
        let trailingNewline = original.hasSuffix("\n")
        let body = trailingNewline ? String(original.dropLast()) : original
        let lines = body.components(separatedBy: "\n")
        let replacement = lines.map { prefix + $0 }.joined(separator: "\n")
            + (trailingNewline ? "\n" : "")
        return MarkdownEditResult(
            text: replacing(source, range: lineRange, with: replacement),
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    private static func insertBlock(
        _ block: String,
        source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        let nsSource = source as NSString
        let needsLeadingNewline = selection.location > 0
            && nsSource.substring(
                with: NSRange(location: selection.location - 1, length: 1)
            ) != "\n"
        let selectionEnd = NSMaxRange(selection)
        let needsTrailingNewline = selectionEnd < nsSource.length
            && nsSource.substring(
                with: NSRange(location: selectionEnd, length: 1)
            ) != "\n"
        let replacement = (needsLeadingNewline ? "\n" : "")
            + block
            + (needsTrailingNewline ? "\n" : "")
        return MarkdownEditResult(
            text: replacing(source, range: selection, with: replacement),
            selection: NSRange(
                location: selection.location + (needsLeadingNewline ? 1 : 0),
                length: (block as NSString).length
            )
        )
    }

    private static func replacing(
        _ source: String,
        range: NSRange,
        with replacement: String
    ) -> String {
        (source as NSString).replacingCharacters(in: range, with: replacement)
    }
}

private extension NSRange {
    nonisolated func clamped(to length: Int) -> NSRange {
        let location = min(max(location, 0), length)
        return NSRange(
            location: location,
            length: min(max(self.length, 0), max(length - location, 0))
        )
    }
}
