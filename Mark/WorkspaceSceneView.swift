//
//  WorkspaceSceneView.swift
//  DiagramDown
//

import SwiftUI

struct WorkspaceSceneView: View {
    @State private var reference: WorkspaceReference?

    var body: some View {
        Group {
            if let reference {
                WorkspaceWindowView(reference: reference)
                    .id(reference.id)
            } else {
                WorkspaceWelcomeView(openFolder: openFolder)
            }
        }
        .focusedSceneValue(
            \.workspaceOpenFolderAction,
            WorkspaceOpenFolderAction(perform: openFolder)
        )
        .task {
            guard reference == nil,
                  let recovered =
                    WorkspaceLaunchRestoration.shared.takeReferenceForLaunch() else {
                return
            }
            reference = recovered
        }
    }

    private func openFolder() {
        guard let selected = WorkspaceFolderPicker.choose() else {
            return
        }
        WorkspaceLaunchRestoration.shared.remember(selected)
        reference = selected
    }
}

private struct WorkspaceWelcomeView: View {
    let openFolder: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Open a Folder", systemImage: "folder")
        } description: {
            Text("Choose a folder containing Markdown files to start a workspace.")
        } actions: {
            Button("Open Folder…", action: openFolder)
                .keyboardShortcut("o", modifiers: .command)
        }
        .frame(minWidth: 760, minHeight: 460)
    }
}
