//
//  WorkspaceCommands.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceOpenFolderAction) private var openFolder
    @FocusedValue(\.workspaceOpenReferenceAction) private var openReference
    @ObservedObject private var restoration = WorkspaceLaunchRestoration.shared

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") {
                openFolder?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openFolder == nil)

            Menu("Open Recent") {
                if restoration.recentWorkspaces.isEmpty {
                    Text("No Recent Folders")
                } else {
                    ForEach(restoration.recentWorkspaces) { recent in
                        Button(recent.displayName) {
                            openReference?(recent.reference)
                        }
                        .help(recent.displayName)
                    }
                    Divider()
                    Button("Clear Menu") {
                        restoration.clearRecentWorkspaces()
                    }
                }
            }
            .disabled(openReference == nil)
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

struct WorkspaceOpenReferenceAction {
    let perform: (WorkspaceReference) -> Void

    func callAsFunction(_ reference: WorkspaceReference) {
        perform(reference)
    }
}

private struct WorkspaceOpenFolderActionKey: FocusedValueKey {
    typealias Value = WorkspaceOpenFolderAction
}

private struct WorkspaceOpenReferenceActionKey: FocusedValueKey {
    typealias Value = WorkspaceOpenReferenceAction
}

struct WorkspaceSaveAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

struct WorkspaceCloseFileAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

private struct WorkspaceSaveActionKey: FocusedValueKey {
    typealias Value = WorkspaceSaveAction
}

private struct WorkspaceCloseFileActionKey: FocusedValueKey {
    typealias Value = WorkspaceCloseFileAction
}

extension FocusedValues {
    var workspaceOpenFolderAction: WorkspaceOpenFolderAction? {
        get { self[WorkspaceOpenFolderActionKey.self] }
        set { self[WorkspaceOpenFolderActionKey.self] = newValue }
    }

    var workspaceOpenReferenceAction: WorkspaceOpenReferenceAction? {
        get { self[WorkspaceOpenReferenceActionKey.self] }
        set { self[WorkspaceOpenReferenceActionKey.self] = newValue }
    }

    var workspaceSaveAction: WorkspaceSaveAction? {
        get { self[WorkspaceSaveActionKey.self] }
        set { self[WorkspaceSaveActionKey.self] = newValue }
    }

    var workspaceCloseFileAction: WorkspaceCloseFileAction? {
        get { self[WorkspaceCloseFileActionKey.self] }
        set { self[WorkspaceCloseFileActionKey.self] = newValue }
    }
}

struct WorkspaceSaveCommands: Commands {
    @FocusedValue(\.workspaceSaveAction) private var save
    @FocusedValue(\.workspaceCloseFileAction) private var closeFile

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                save?()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(save == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Close File") {
                closeFile?()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(closeFile == nil)
        }
    }
}
