//
//  PreviewDocument.swift
//  DiagramDown
//

import Foundation

nonisolated struct PreviewSourceRange: Hashable, Sendable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int

    static let documentStart = PreviewSourceRange(
        startLine: 1,
        startColumn: 1,
        endLine: 1,
        endColumn: 1
    )

    func contains(line: Int) -> Bool {
        (startLine...max(startLine, endLine)).contains(line)
    }

    func overlaps(_ other: PreviewSourceRange) -> Bool {
        startLine <= other.endLine && other.startLine <= endLine
    }
}

nonisolated struct PreviewBlockID: Hashable, Sendable, Identifiable, CustomStringConvertible {
    let rawValue: String

    var id: String { rawValue }
    var description: String { rawValue }
}

nonisolated struct PreviewDocument: Equatable, Sendable {
    let revision: UInt64
    let sourceDigest: String
    let blocks: [PreviewBlock]
    let lineCount: Int

    static let empty = PreviewDocument(
        revision: 0,
        sourceDigest: "",
        blocks: [],
        lineCount: 1
    )
}

nonisolated struct PreviewBlock: Identifiable, Equatable, Sendable {
    let id: PreviewBlockID
    let sourceRange: PreviewSourceRange
    let content: PreviewBlockContent
    let fingerprint: String

    func replacingID(_ id: PreviewBlockID) -> PreviewBlock {
        PreviewBlock(
            id: id,
            sourceRange: sourceRange,
            content: content,
            fingerprint: fingerprint
        )
    }
}

nonisolated indirect enum PreviewBlockContent: Equatable, Sendable {
    case heading(level: Int, inline: PreviewInlineContent)
    case paragraph(PreviewInlineContent)
    case blockQuote([PreviewBlock])
    case unorderedList(items: [PreviewListItem])
    case orderedList(start: Int, items: [PreviewListItem])
    case table(PreviewTable)
    case code(language: CodeLanguage?, rawLanguage: String?, source: String)
    case mermaid(source: String)
    case d2(source: String)
    case thematicBreak
    case image(PreviewImage)
    case rawText(String)

    var kind: String {
        switch self {
        case .heading: "heading"
        case .paragraph: "paragraph"
        case .blockQuote: "quote"
        case .unorderedList: "unordered-list"
        case .orderedList: "ordered-list"
        case .table: "table"
        case .code: "code"
        case .mermaid: "mermaid"
        case .d2: "d2"
        case .thematicBreak: "thematic-break"
        case .image: "image"
        case .rawText: "raw-text"
        }
    }
}

nonisolated struct PreviewListItem: Equatable, Sendable {
    let checkbox: Bool?
    let blocks: [PreviewBlock]
    let sourceRange: PreviewSourceRange
}

nonisolated struct PreviewTable: Equatable, Sendable {
    nonisolated enum Alignment: Equatable, Sendable {
        case leading
        case center
        case trailing
    }

    let headers: [PreviewInlineContent]
    let rows: [[PreviewInlineContent]]
    let alignments: [Alignment]
}

nonisolated struct PreviewImage: Equatable, Sendable {
    let source: String
    let title: String?
    let alt: String
}

nonisolated struct PreviewInlineContent: Equatable, Sendable {
    let nodes: [PreviewInlineNode]

    static let empty = PreviewInlineContent(nodes: [])

    var plainText: String {
        nodes.map(\.plainText).joined()
    }
}

nonisolated indirect enum PreviewInlineNode: Equatable, Sendable {
    case text(String)
    case emphasis([PreviewInlineNode])
    case strong([PreviewInlineNode])
    case strikethrough([PreviewInlineNode])
    case code(String)
    case link(destination: String, title: String?, children: [PreviewInlineNode])
    case image(source: String, title: String?, alt: String)
    case softBreak
    case hardBreak
    case rawText(String)

    var plainText: String {
        switch self {
        case .text(let text), .code(let text), .rawText(let text):
            text
        case .emphasis(let children),
             .strong(let children),
             .strikethrough(let children):
            children.map(\.plainText).joined()
        case .link(_, _, let children):
            children.map(\.plainText).joined()
        case .image(_, _, let alt):
            alt
        case .softBreak:
            " "
        case .hardBreak:
            "\n"
        }
    }
}
