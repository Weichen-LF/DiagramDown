//
//  D2PreviewSettingsView.swift
//  DiagramDown
//

import SwiftUI

enum D2PreviewPreferences {
    static let layoutKey = "D2Preview.layout"
    static let lightThemeIDKey = "D2Preview.lightThemeID"
    static let darkThemeIDKey = "D2Preview.darkThemeID"
    static let paddingKey = "D2Preview.padding"
    static let sketchKey = "D2Preview.sketch"
}

struct D2PreviewSettingsView: View {
    @AppStorage(D2PreviewPreferences.layoutKey) private var layout =
        D2RenderConfiguration.Layout.dagre.rawValue
    @AppStorage(D2PreviewPreferences.lightThemeIDKey) private var lightThemeID =
        D2RenderConfiguration.preview.lightThemeID
    @AppStorage(D2PreviewPreferences.darkThemeIDKey) private var darkThemeID =
        D2RenderConfiguration.preview.darkThemeID
    @AppStorage(D2PreviewPreferences.paddingKey) private var padding =
        D2RenderConfiguration.preview.padding
    @AppStorage(D2PreviewPreferences.sketchKey) private var sketch =
        D2RenderConfiguration.preview.sketch

    var body: some View {
        Form {
            Section("D2 Preview") {
                Picker("Layout", selection: $layout) {
                    ForEach(D2RenderConfiguration.Layout.allCases) { layout in
                        Text(layout.displayName).tag(layout.rawValue)
                    }
                }

                Picker("Light theme", selection: $lightThemeID) {
                    ForEach(Self.lightThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                Picker("Dark theme", selection: $darkThemeID) {
                    ForEach(Self.darkThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                Stepper("Padding: \(padding) pt", value: $padding, in: 0...200, step: 8)
                Toggle("Sketch style", isOn: $sketch)
            }

            Section {
                HStack {
                    Text("Changes apply to every open preview.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults", action: restoreDefaults)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
    }

    private func restoreDefaults() {
        let defaults = D2RenderConfiguration.preview
        layout = defaults.layout.rawValue
        lightThemeID = defaults.lightThemeID
        darkThemeID = defaults.darkThemeID
        padding = defaults.padding
        sketch = defaults.sketch
    }

    private struct Theme: Identifiable {
        let id: Int
        let name: String
    }

    private static let lightThemes = [
        Theme(id: 0, name: "Neutral default"),
        Theme(id: 1, name: "Neutral grey"),
        Theme(id: 3, name: "Flagship Terrastruct"),
        Theme(id: 4, name: "Cool classics"),
        Theme(id: 5, name: "Mixed berry blue"),
        Theme(id: 6, name: "Grape soda"),
        Theme(id: 100, name: "Vanilla nitro cola"),
        Theme(id: 101, name: "Orange creamsicle"),
        Theme(id: 102, name: "Shirley temple"),
        Theme(id: 103, name: "Earth tones"),
        Theme(id: 104, name: "Everglade green"),
        Theme(id: 105, name: "Buttered toast"),
    ]

    private static let darkThemes = [
        Theme(id: 200, name: "Dark mauve"),
        Theme(id: 201, name: "Dark flagship"),
    ]
}
