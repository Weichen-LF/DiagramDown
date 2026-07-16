//
//  PreviewCommands.swift
//  DiagramDown
//

import Combine
import SwiftUI

enum PreviewZoom {
    static let minimum = 50
    static let maximum = 200
    static let step = 10
    static let defaultValue = 100
    static let menuValues = [50, 75, 100, 125, 150, 175, 200]

    static func clamped(_ value: Int) -> Int {
        min(max(value, minimum), maximum)
    }

    static func scaled(_ value: Int, by scale: Double) -> Int {
        guard scale.isFinite else {
            return clamped(value)
        }

        let scaledValue = Double(value) * scale
        if scaledValue <= Double(minimum) {
            return minimum
        }
        if scaledValue >= Double(maximum) {
            return maximum
        }
        return Int(scaledValue.rounded())
    }
}

@MainActor
final class PreviewController: ObservableObject {
    weak var coordinator: MarkdownPreviewView.Coordinator?

    func exportPDF() {
        coordinator?.exportPreviewPDF()
    }
}

struct PreviewExportPDFAction {
    let perform: () -> Void

    func callAsFunction() {
        perform()
    }
}

private struct PreviewExportPDFActionKey: FocusedValueKey {
    typealias Value = PreviewExportPDFAction
}

extension FocusedValues {
    var previewExportPDFAction: PreviewExportPDFAction? {
        get { self[PreviewExportPDFActionKey.self] }
        set { self[PreviewExportPDFActionKey.self] = newValue }
    }
}

struct PreviewCommands: Commands {
    @AppStorage(PreviewPreferences.zoomKey) private var zoom = PreviewZoom.defaultValue
    @FocusedValue(\.previewExportPDFAction) private var exportPDF

    var body: some Commands {
        CommandMenu("Preview") {
            Button("Zoom In") {
                zoom = PreviewZoom.clamped(zoom + PreviewZoom.step)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(PreviewZoom.clamped(zoom) >= PreviewZoom.maximum)

            Button("Zoom Out") {
                zoom = PreviewZoom.clamped(zoom - PreviewZoom.step)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(PreviewZoom.clamped(zoom) <= PreviewZoom.minimum)

            Button("Actual Size") {
                zoom = PreviewZoom.defaultValue
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(PreviewZoom.clamped(zoom) == PreviewZoom.defaultValue)

            Divider()

            Button("Export Preview as PDF…") {
                exportPDF?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportPDF == nil)
        }
    }
}
