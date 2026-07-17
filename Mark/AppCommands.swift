//
//  AppCommands.swift
//  DiagramDown
//

import AppKit
import SwiftUI

enum DiagramDownLinks {
    static let project = URL(string: "https://github.com/Weichen-LF/DiagramDown")!
    static let feedback = URL(
        string: "https://github.com/Weichen-LF/DiagramDown/issues/new/choose"
    )!
    static let releaseNotes = URL(
        string: "https://github.com/Weichen-LF/DiagramDown/releases/latest"
    )!
}

enum ExampleDocument {
    static let resourceName = "DiagramDown-Example"

    static func source(in bundle: Bundle = .main) throws -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: "md") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

enum EditorGuidance {
    static let placeholder =
        "Start writing Markdown, or choose Help > Open Example Document."
}

@MainActor
enum AppHelp {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func showKeyboardShortcuts() {
        let alert = NSAlert()
        alert.messageText = "DiagramDown Keyboard Shortcuts"
        alert.informativeText = """
        New Document        ⌘N
        Open…               ⌘O
        Save                ⌘S
        Find                ⌘F

        Zoom In             ⌘+
        Zoom Out            ⌘−
        Actual Size         ⌘0
        Export Preview PDF  ⇧⌘E

        Focused diagrams also support +, −, 0, and trackpad pinch-to-zoom.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func showExampleError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "The example document could not be opened."
        alert.runModal()
    }
}

struct AppCommands: Commands {
    @Environment(\.newDocument) private var newDocument

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Open Example Document") {
                do {
                    let source = try ExampleDocument.source()
                    newDocument(MarkdownDocument(text: source))
                } catch {
                    AppHelp.showExampleError(error)
                }
            }

            Button("Keyboard Shortcuts…") {
                AppHelp.showKeyboardShortcuts()
            }

            Button("Export Diagnostics…") {
                DiagnosticsExporter.export()
            }

            Divider()

            Button("DiagramDown on GitHub") {
                AppHelp.open(DiagramDownLinks.project)
            }

            Button("Report an Issue…") {
                AppHelp.open(DiagramDownLinks.feedback)
            }

            Button("Release Notes") {
                AppHelp.open(DiagramDownLinks.releaseNotes)
            }
        }
    }
}
