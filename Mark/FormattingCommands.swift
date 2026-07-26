//
//  FormattingCommands.swift
//  DiagramDown
//

import SwiftUI

struct FormatDocumentAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

struct MarkdownEditMenuAction {
    let perform: (MarkdownEditAction) -> Void

    func callAsFunction(_ action: MarkdownEditAction) {
        perform(action)
    }
}

private struct FormatDocumentActionKey: FocusedValueKey {
    typealias Value = FormatDocumentAction
}

private struct MarkdownEditMenuActionKey: FocusedValueKey {
    typealias Value = MarkdownEditMenuAction
}

extension FocusedValues {
    var formatDocumentAction: FormatDocumentAction? {
        get { self[FormatDocumentActionKey.self] }
        set { self[FormatDocumentActionKey.self] = newValue }
    }

    var markdownEditMenuAction: MarkdownEditMenuAction? {
        get { self[MarkdownEditMenuActionKey.self] }
        set { self[MarkdownEditMenuActionKey.self] = newValue }
    }
}

struct FormattingCommands: Commands {
    @FocusedValue(\.formatDocumentAction) private var formatDocument
    @FocusedValue(\.markdownEditMenuAction) private var markdownEdit

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Menu("Markdown") {
                Button("Bold") { markdownEdit?(.bold) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { markdownEdit?(.italic) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Strikethrough") { markdownEdit?(.strikethrough) }
                Button("Inline Code") { markdownEdit?(.inlineCode) }
                Button("Link") { markdownEdit?(.link) }
                    .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Heading") { markdownEdit?(.heading) }
                Button("Block Quote") { markdownEdit?(.blockQuote) }
                Button("Bulleted List") { markdownEdit?(.unorderedList) }
                Button("Numbered List") { markdownEdit?(.orderedList) }
                Button("Task List") { markdownEdit?(.taskList) }

                Divider()

                Button("Code Block") { markdownEdit?(.codeBlock) }
                Button("Table") { markdownEdit?(.table) }
                Button("Horizontal Rule") { markdownEdit?(.horizontalRule) }
            }
            .disabled(markdownEdit == nil)

            Button("Format Document") {
                formatDocument?()
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])
            .disabled(formatDocument == nil)
        }
    }
}
