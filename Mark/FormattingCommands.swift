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

private struct FormatDocumentActionKey: FocusedValueKey {
    typealias Value = FormatDocumentAction
}

extension FocusedValues {
    var formatDocumentAction: FormatDocumentAction? {
        get { self[FormatDocumentActionKey.self] }
        set { self[FormatDocumentActionKey.self] = newValue }
    }
}

struct FormattingCommands: Commands {
    @FocusedValue(\.formatDocumentAction) private var formatDocument

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Format Document") {
                formatDocument?()
            }
            .keyboardShortcut("f", modifiers: [.option, .shift])
            .disabled(formatDocument == nil)
        }
    }
}
