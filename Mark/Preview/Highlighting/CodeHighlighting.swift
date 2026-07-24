//
//  CodeHighlighting.swift
//  DiagramDown
//

import AppKit
import Foundation
import SwiftUI

protocol CodeHighlighting: Sendable {
    func highlight(
        source: String,
        language: CodeLanguage?,
        theme: CodeTheme
    ) async -> AttributedString
}

enum SyntaxToken: String, Hashable, Sendable {
    case plain
    case comment
    case documentationComment
    case keyword
    case string
    case number
    case type
    case function
    case method
    case property
    case variable
    case parameter
    case constant
    case attribute
    case tag
    case operatorSymbol
    case punctuation
    case label
    case escape
    case embedded
}

struct SyntaxStyle: @unchecked Sendable {
    let color: NSColor
    let bold: Bool
    let italic: Bool

    init(color: NSColor, bold: Bool = false, italic: Bool = false) {
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

struct CodeTheme: Hashable, @unchecked Sendable {
    let id: String
    let background: NSColor
    let foreground: NSColor
    let styles: [SyntaxToken: SyntaxStyle]

    static func == (lhs: CodeTheme, rhs: CodeTheme) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated enum SyntaxCaptureNormalizer {
    static func token(for capture: String) -> SyntaxToken {
        let components = capture.lowercased().split(separator: ".")
        for component in components {
            switch component {
            case "comment":
                return components.contains("documentation")
                    ? .documentationComment
                    : .comment
            case "keyword", "conditional", "repeat", "exception", "include":
                return .keyword
            case "string", "character":
                return .string
            case "escape":
                return .escape
            case "number", "float", "boolean":
                return .number
            case "type", "constructor":
                return .type
            case "function":
                return components.contains("method") ? .method : .function
            case "method":
                return .method
            case "property", "field":
                return .property
            case "variable":
                if components.contains("parameter") {
                    return .parameter
                }
                if components.contains("builtin") {
                    return .constant
                }
                return .variable
            case "parameter":
                return .parameter
            case "constant":
                return .constant
            case "attribute":
                return .attribute
            case "tag":
                return .tag
            case "operator":
                return .operatorSymbol
            case "punctuation":
                return .punctuation
            case "label":
                return .label
            case "embedded":
                return .embedded
            default:
                continue
            }
        }
        return .plain
    }
}

extension CodeTheme {
    static func resolved(
        markdownTheme: MarkdownPreviewTheme,
        appearance: ColorScheme
    ) -> CodeTheme {
        let dark = appearance == .dark

        switch (markdownTheme, dark) {
        case (.github, false):
            return make(
                id: "github-light",
                background: "#f6f8fa",
                foreground: "#24292f",
                comment: "#6e7781",
                keyword: "#cf222e",
                string: "#0a3069",
                number: "#0550ae",
                type: "#8250df",
                function: "#8250df"
            )
        case (.github, true):
            return make(
                id: "github-dark",
                background: "#161b22",
                foreground: "#c9d1d9",
                comment: "#8b949e",
                keyword: "#ff7b72",
                string: "#a5d6ff",
                number: "#79c0ff",
                type: "#d2a8ff",
                function: "#d2a8ff"
            )
        case (.paper, false):
            return make(
                id: "paper-light",
                background: "#f4efe4",
                foreground: "#302c27",
                comment: "#81786c",
                keyword: "#8f3b32",
                string: "#3f6f62",
                number: "#845d2f",
                type: "#6c4f8f",
                function: "#365f8d"
            )
        case (.paper, true):
            return make(
                id: "paper-dark",
                background: "#24211d",
                foreground: "#e6dfd2",
                comment: "#9f968a",
                keyword: "#ef9185",
                string: "#9dc9b8",
                number: "#ddb178",
                type: "#c4a4e6",
                function: "#98bce2"
            )
        case (.diagramDown, false):
            return make(
                id: "diagramdown-light",
                background: "#f4f7fb",
                foreground: "#172033",
                comment: "#738096",
                keyword: "#b4235b",
                string: "#087f5b",
                number: "#2f6feb",
                type: "#7048e8",
                function: "#2458a6"
            )
        case (.diagramDown, true):
            return make(
                id: "diagramdown-dark",
                background: "#151a23",
                foreground: "#dce4f2",
                comment: "#8390a6",
                keyword: "#ff7ca8",
                string: "#72d6b0",
                number: "#83b7ff",
                type: "#bba1ff",
                function: "#8cbaff"
            )
        }
    }

    private static func make(
        id: String,
        background: String,
        foreground: String,
        comment: String,
        keyword: String,
        string: String,
        number: String,
        type: String,
        function: String
    ) -> CodeTheme {
        let foregroundColor = NSColor(hex: foreground)
        return CodeTheme(
            id: id,
            background: NSColor(hex: background),
            foreground: foregroundColor,
            styles: [
                .plain: SyntaxStyle(color: foregroundColor),
                .comment: SyntaxStyle(color: NSColor(hex: comment), italic: true),
                .documentationComment: SyntaxStyle(
                    color: NSColor(hex: comment),
                    italic: true
                ),
                .keyword: SyntaxStyle(color: NSColor(hex: keyword), bold: true),
                .string: SyntaxStyle(color: NSColor(hex: string)),
                .escape: SyntaxStyle(color: NSColor(hex: keyword)),
                .number: SyntaxStyle(color: NSColor(hex: number)),
                .type: SyntaxStyle(color: NSColor(hex: type)),
                .function: SyntaxStyle(color: NSColor(hex: function)),
                .method: SyntaxStyle(color: NSColor(hex: function)),
                .property: SyntaxStyle(color: NSColor(hex: number)),
                .variable: SyntaxStyle(color: foregroundColor),
                .parameter: SyntaxStyle(color: NSColor(hex: foreground)),
                .constant: SyntaxStyle(color: NSColor(hex: number)),
                .attribute: SyntaxStyle(color: NSColor(hex: type)),
                .tag: SyntaxStyle(color: NSColor(hex: keyword)),
                .operatorSymbol: SyntaxStyle(color: NSColor(hex: keyword)),
                .punctuation: SyntaxStyle(color: NSColor(hex: comment)),
                .label: SyntaxStyle(color: NSColor(hex: type)),
                .embedded: SyntaxStyle(color: NSColor(hex: string)),
            ]
        )
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16)
            ?? 0
        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
