//
//  MarkdownParserService.swift
//  DiagramDown
//

import CryptoKit
import Foundation
import Markdown

actor MarkdownParserService {
    static let shared = MarkdownParserService()

    func parse(
        source: String,
        revision: UInt64,
        previous: PreviewDocument?
    ) throws -> PreviewDocument {
        try Task.checkCancellation()

        let syntax = Document(parsing: source)
        var visitor = MarkdownPreviewVisitor(source: source)
        let unreconciled = visitor.convertDocument(syntax)
        try Task.checkCancellation()

        let blocks = PreviewDocumentReconciler().reconcile(
            newBlocks: unreconciled,
            previousBlocks: previous?.blocks ?? []
        )
        return PreviewDocument(
            revision: revision,
            sourceDigest: Self.digest(source),
            blocks: blocks,
            lineCount: max(1, source.reduce(into: 1) { count, character in
                if character == "\n" {
                    count += 1
                }
            })
        )
    }

    nonisolated static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

nonisolated private struct MarkdownPreviewVisitor {
    let source: String
    private var fingerprintOccurrences: [String: Int] = [:]

    init(source: String) {
        self.source = source
    }

    mutating func convertDocument(_ document: Document) -> [PreviewBlock] {
        document.children.flatMap {
            convertBlock($0, inheritedRange: .documentStart)
        }
    }

    private mutating func convertBlock(
        _ markup: Markup,
        inheritedRange: PreviewSourceRange
    ) -> [PreviewBlock] {
        let range = sourceRange(for: markup) ?? inheritedRange
        let content: PreviewBlockContent?

        switch markup {
        case let heading as Heading:
            content = .heading(
                level: min(max(heading.level, 1), 6),
                inline: convertInlineChildren(heading)
            )

        case let paragraph as Paragraph:
            let inline = convertInlineChildren(paragraph)
            if inline.nodes.count == 1,
               case let .image(source, title, alt) = inline.nodes[0] {
                content = .image(PreviewImage(source: source, title: title, alt: alt))
            } else {
                content = .paragraph(inline)
            }

        case let quote as BlockQuote:
            let children = quote.children.flatMap {
                convertBlock($0, inheritedRange: range)
            }
            content = .blockQuote(children)

        case let list as UnorderedList:
            content = .unorderedList(
                items: list.listItems.map { convertListItem($0, inheritedRange: range) }
            )

        case let list as OrderedList:
            content = .orderedList(
                start: Int(list.startIndex),
                items: list.listItems.map { convertListItem($0, inheritedRange: range) }
            )

        case let table as Table:
            content = .table(convertTable(table))

        case let code as CodeBlock:
            let rawLanguage = code.language?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            switch CodeLanguage.resolve(rawLanguage) {
            case .mermaid:
                content = .mermaid(source: code.code)
            case .d2:
                content = .d2(source: code.code)
            case let language:
                content = .code(
                    language: language,
                    rawLanguage: rawLanguage,
                    source: code.code
                )
            }

        case is ThematicBreak:
            content = .thematicBreak

        case let html as HTMLBlock:
            content = .rawText(html.rawHTML)

        default:
            let nested = markup.children.flatMap {
                convertBlock($0, inheritedRange: range)
            }
            return nested
        }

        guard let content else {
            return []
        }
        return [makeBlock(content: content, range: range)]
    }

    private mutating func convertListItem(
        _ item: ListItem,
        inheritedRange: PreviewSourceRange
    ) -> PreviewListItem {
        let range = sourceRange(for: item) ?? inheritedRange
        let checkbox: Bool?
        switch item.checkbox {
        case .checked:
            checkbox = true
        case .unchecked:
            checkbox = false
        case nil:
            checkbox = nil
        }

        return PreviewListItem(
            checkbox: checkbox,
            blocks: item.children.flatMap {
                convertBlock($0, inheritedRange: range)
            },
            sourceRange: range
        )
    }

    private func convertTable(_ table: Table) -> PreviewTable {
        PreviewTable(
            headers: table.head.cells.map(convertInlineChildren),
            rows: table.body.rows.map { row in
                row.cells.map(convertInlineChildren)
            },
            alignments: table.columnAlignments.map { alignment in
                switch alignment {
                case .left, nil:
                    .leading
                case .center:
                    .center
                case .right:
                    .trailing
                }
            }
        )
    }

    private func convertInlineChildren(_ markup: Markup) -> PreviewInlineContent {
        PreviewInlineContent(nodes: markup.children.flatMap(convertInline))
    }

    private func convertInline(_ markup: Markup) -> [PreviewInlineNode] {
        switch markup {
        case let text as Markdown.Text:
            [.text(text.string)]
        case let emphasis as Emphasis:
            [.emphasis(emphasis.children.flatMap(convertInline))]
        case let strong as Strong:
            [.strong(strong.children.flatMap(convertInline))]
        case let strikethrough as Strikethrough:
            [.strikethrough(strikethrough.children.flatMap(convertInline))]
        case let code as InlineCode:
            [.code(code.code)]
        case let link as Markdown.Link:
            [.link(
                destination: link.destination ?? "",
                title: link.title,
                children: link.children.flatMap(convertInline)
            )]
        case let image as Markdown.Image:
            [.image(
                source: image.source ?? "",
                title: image.title,
                alt: image.children.flatMap(convertInline).map(\.plainText).joined()
            )]
        case is SoftBreak:
            [.softBreak]
        case is LineBreak:
            [.hardBreak]
        case let html as InlineHTML:
            [.rawText(html.rawHTML)]
        default:
            markup.children.flatMap(convertInline)
        }
    }

    private mutating func makeBlock(
        content: PreviewBlockContent,
        range: PreviewSourceRange
    ) -> PreviewBlock {
        let normalized = String(describing: content)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let fingerprint = MarkdownParserService.digest(
            "\(content.kind)\u{0}\(normalized)"
        )
        let occurrence = fingerprintOccurrences[fingerprint, default: 0]
        fingerprintOccurrences[fingerprint] = occurrence + 1
        let shortHash = String(fingerprint.prefix(20))

        return PreviewBlock(
            id: PreviewBlockID(rawValue: "\(content.kind)-\(shortHash)-\(occurrence)"),
            sourceRange: range,
            content: content,
            fingerprint: fingerprint
        )
    }

    private func sourceRange(for markup: Markup) -> PreviewSourceRange? {
        guard let range = markup.range else {
            return nil
        }

        let maximumLine = 10_000_000
        let startLine = min(max(range.lowerBound.line, 1), maximumLine)
        let endLine = min(max(range.upperBound.line, startLine), maximumLine)
        return PreviewSourceRange(
            startLine: startLine,
            startColumn: max(range.lowerBound.column, 1),
            endLine: endLine,
            endColumn: max(range.upperBound.column, 1)
        )
    }
}
