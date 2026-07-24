//
//  DiagramDownApp.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

@main
struct DiagramDownApp: App {
    @AppStorage(PreviewPreferences.appearanceKey) private var appearance =
        AppAppearance.system.rawValue

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .preferredColorScheme(preferredColorScheme)
        }
        .commands {
            FormattingCommands()
            PreviewCommands()
            WorkspaceCommands()
            AppCommands()
        }

        WindowGroup("Workspace", for: WorkspaceReference.self) { $reference in
            if let reference {
                WorkspaceWindowView(reference: reference)
                    .preferredColorScheme(preferredColorScheme)
            }
        }
        .commands {
            FormattingCommands()
            PreviewCommands()
            WorkspaceCommands()
            AppCommands()
        }
        .defaultSize(width: 1_120, height: 720)

        Settings {
            PreviewSettingsView()
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .system).colorScheme
    }
}
