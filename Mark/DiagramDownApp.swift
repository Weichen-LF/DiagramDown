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
        WindowGroup {
            WorkspaceSceneView()
                .preferredColorScheme(preferredColorScheme)
        }
        .commands {
            FormattingCommands()
            PreviewCommands()
            WorkspaceCommands()
            WorkspaceSaveCommands()
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
