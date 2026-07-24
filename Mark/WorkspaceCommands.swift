//
//  WorkspaceCommands.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct WorkspaceCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Folder…") {
                openFolder()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        do {
            openWindow(value: try WorkspaceReference.create(for: folderURL))
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The folder could not be opened."
            alert.runModal()
        }
    }
}

struct WorkspaceSaveAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

private struct WorkspaceSaveActionKey: FocusedValueKey {
    typealias Value = WorkspaceSaveAction
}

extension FocusedValues {
    var workspaceSaveAction: WorkspaceSaveAction? {
        get { self[WorkspaceSaveActionKey.self] }
        set { self[WorkspaceSaveActionKey.self] = newValue }
    }
}

struct WorkspaceSaveCommands: Commands {
    @FocusedValue(\.workspaceSaveAction) private var save

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                save?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(save == nil)
        }
    }
}
