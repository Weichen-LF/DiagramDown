//
//  WorkspaceCommands.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceOpenFolderAction) private var openFolder

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                openFolder?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openFolder == nil)
        }
    }
}

@MainActor
enum WorkspaceFolderPicker {
    static func choose() -> WorkspaceReference? {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return nil
        }

        do {
            return try WorkspaceReference.create(for: folderURL)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The folder could not be opened."
            alert.runModal()
            return nil
        }
    }
}

struct WorkspaceOpenFolderAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

private struct WorkspaceOpenFolderActionKey: FocusedValueKey {
    typealias Value = WorkspaceOpenFolderAction
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
    var workspaceOpenFolderAction: WorkspaceOpenFolderAction? {
        get { self[WorkspaceOpenFolderActionKey.self] }
        set { self[WorkspaceOpenFolderActionKey.self] = newValue }
    }

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
