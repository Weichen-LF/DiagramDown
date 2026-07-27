//
//  PreviewSettingsView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

enum PreviewPreferences {
    static let appearanceKey = "Appearance.mode"
    static let markdownThemeKey = "MarkdownPreview.theme"
    static let mermaidLightThemeKey = "MermaidPreview.lightTheme"
    static let mermaidDarkThemeKey = "MermaidPreview.darkTheme"
    static let zoomKey = "MarkdownPreview.zoom"
    static let d2LayoutKey = "D2Preview.layout"
    static let d2LightThemeIDKey = "D2Preview.lightThemeID"
    static let d2DarkThemeIDKey = "D2Preview.darkThemeID"
    static let d2PaddingKey = "D2Preview.padding"
    static let d2SketchKey = "D2Preview.sketch"
}

enum AppAppearance: String, CaseIterable, Hashable, Identifiable, Sendable {
    case system
    case light
    case dark

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            "Follow System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

enum MarkdownPreviewTheme: String, CaseIterable, Hashable, Identifiable, Sendable {
    case diagramDown
    case github
    case paper

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .diagramDown:
            "DiagramDown"
        case .github:
            "GitHub"
        case .paper:
            "Paper"
        }
    }
}

enum MermaidPreviewTheme: String, CaseIterable, Hashable, Identifiable, Sendable {
    case `default`
    case neutral
    case forest
    case dark

    nonisolated var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:
            "Default"
        case .neutral:
            "Neutral"
        case .forest:
            "Forest"
        case .dark:
            "Dark"
        }
    }
}

struct PreviewConfiguration: Hashable, Sendable {
    let appearance: AppAppearance
    let markdownTheme: MarkdownPreviewTheme
    let mermaidLightTheme: MermaidPreviewTheme
    let mermaidDarkTheme: MermaidPreviewTheme
    let d2: D2RenderConfiguration
}

struct PreviewSettingsView: View {
    @AppStorage(PreviewPreferences.appearanceKey) private var appearance =
        AppAppearance.system.rawValue
    @AppStorage(PreviewPreferences.markdownThemeKey) private var markdownTheme =
        MarkdownPreviewTheme.diagramDown.rawValue
    @AppStorage(PreviewPreferences.mermaidLightThemeKey) private var mermaidLightTheme =
        MermaidPreviewTheme.default.rawValue
    @AppStorage(PreviewPreferences.mermaidDarkThemeKey) private var mermaidDarkTheme =
        MermaidPreviewTheme.dark.rawValue
    @AppStorage(PreviewPreferences.zoomKey) private var zoom = PreviewZoom.defaultValue
    @AppStorage(PreviewPreferences.d2LayoutKey) private var d2Layout =
        D2RenderConfiguration.Layout.dagre.rawValue
    @AppStorage(PreviewPreferences.d2LightThemeIDKey) private var d2LightThemeID =
        D2RenderConfiguration.preview.lightThemeID
    @AppStorage(PreviewPreferences.d2DarkThemeIDKey) private var d2DarkThemeID =
        D2RenderConfiguration.preview.darkThemeID
    @AppStorage(PreviewPreferences.d2PaddingKey) private var d2Padding =
        D2RenderConfiguration.preview.padding
    @AppStorage(PreviewPreferences.d2SketchKey) private var d2Sketch =
        D2RenderConfiguration.preview.sketch
    @State private var mermaidToolStatus = DiagramToolStatus.missing
    @State private var d2ToolStatus = DiagramToolStatus.missing
    @State private var isRefreshingTools = false
    @State private var isClearingCaches = false
    @State private var showsClearCachesConfirmation = false
    @State private var cacheStatusMessage: String?
    @State private var cacheStatusIsError = false

    var body: some View {
        Form {
            Section("Diagram Tools") {
                toolStatusRow(kind: .mermaid, status: mermaidToolStatus)
                Divider()
                toolStatusRow(kind: .d2, status: d2ToolStatus)

                HStack {
                    Text("Diagram rendering uses command-line tools installed on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await refreshTools() }
                    } label: {
                        if isRefreshingTools {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshingTools)
                }
            }

            Section("Appearance") {
                Picker("Color mode", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Markdown Preview") {
                Picker("Theme", selection: $markdownTheme) {
                    ForEach(MarkdownPreviewTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                Stepper(
                    "Zoom: \(PreviewZoom.clamped(zoom))%",
                    value: $zoom,
                    in: PreviewZoom.minimum...PreviewZoom.maximum,
                    step: PreviewZoom.step
                )
            }

            Section("Mermaid Preview") {
                Picker("Light theme", selection: $mermaidLightTheme) {
                    ForEach(MermaidPreviewTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
                Picker("Dark theme", selection: $mermaidDarkTheme) {
                    ForEach(MermaidPreviewTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme.rawValue)
                    }
                }
            }

            Section("D2 Preview") {
                Picker("Layout", selection: $d2Layout) {
                    ForEach(D2RenderConfiguration.Layout.allCases) { layout in
                        Text(layout.displayName).tag(layout.rawValue)
                    }
                }

                Picker("Light theme", selection: $d2LightThemeID) {
                    ForEach(Self.d2LightThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                Picker("Dark theme", selection: $d2DarkThemeID) {
                    ForEach(Self.d2DarkThemes) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }

                Stepper(
                    "Padding: \(d2Padding) pt",
                    value: $d2Padding,
                    in: 0...200,
                    step: 8
                )
                Toggle("Sketch style", isOn: $d2Sketch)
            }

            Section("Caches") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview caches")
                        Text("Clear syntax highlighting and rendered diagram caches.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showsClearCachesConfirmation = true
                    } label: {
                        if isClearingCaches {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Clear All Caches…")
                        }
                    }
                    .disabled(isClearingCaches)
                }

                if let cacheStatusMessage {
                    Text(cacheStatusMessage)
                        .font(.caption)
                        .foregroundStyle(cacheStatusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section {
                HStack {
                    Text("Changes apply to every open document.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults", action: restoreDefaults)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 820)
        .task {
            await refreshTools()
        }
        .confirmationDialog(
            "Clear all preview caches?",
            isPresented: $showsClearCachesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Caches", role: .destructive) {
                Task { await clearAllCaches() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Cached syntax highlighting and rendered diagram files will be removed. They will be regenerated when needed.")
        }
    }

    @ViewBuilder
    private func toolStatusRow(
        kind: DiagramToolKind,
        status: DiagramToolStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Label(kind.displayName, systemImage: statusIcon(status))
                    .font(.headline)
                    .foregroundStyle(statusColor(status))
                Spacer()
                Button("Choose…") {
                    chooseExecutable(for: kind)
                }
                if UserDefaults.standard.string(
                    forKey: kind.customPathPreferenceKey
                ) != nil {
                    Button("Use Automatically Detected") {
                        Task {
                            let updated = await DiagramToolRegistry.shared
                                .setCustomExecutable(nil, for: kind)
                            apply(updated, for: kind)
                        }
                    }
                }
            }

            switch status {
            case .installed(let tool):
                Text(tool.version)
                    .font(.subheadline)
                Text(tool.executableURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            case .missing:
                Text("Not installed. Diagrams of this type are shown as code blocks.")
                    .font(.subheadline)
                installCommandRow(kind.installCommand)
            case .invalid(let path, let message):
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                installCommandRow(kind.installCommand)
            }
        }
        .padding(.vertical, 3)
    }

    private func installCommandRow(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .help("Copy installation command")
        }
        .padding(7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusIcon(_ status: DiagramToolStatus) -> String {
        switch status {
        case .installed: "checkmark.circle.fill"
        case .missing: "questionmark.circle"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: DiagramToolStatus) -> Color {
        switch status {
        case .installed: .green
        case .missing: .secondary
        case .invalid: .red
        }
    }

    private func refreshTools() async {
        isRefreshingTools = true
        let statuses = await DiagramToolRegistry.shared.refreshAll(notifyViews: true)
        mermaidToolStatus = statuses[.mermaid] ?? .missing
        d2ToolStatus = statuses[.d2] ?? .missing
        isRefreshingTools = false
    }

    @MainActor
    private func clearAllCaches() async {
        isClearingCaches = true
        cacheStatusMessage = nil
        cacheStatusIsError = false
        defer { isClearingCaches = false }

        do {
            try await PreviewCacheController.purgeAll()
            let defaults = UserDefaults.standard
            defaults.set(
                defaults.integer(forKey: DiagramToolRegistry.revisionPreferenceKey) &+ 1,
                forKey: DiagramToolRegistry.revisionPreferenceKey
            )
            cacheStatusMessage = "All preview caches were cleared."
        } catch {
            cacheStatusIsError = true
            cacheStatusMessage = "Some caches could not be cleared: \(error.localizedDescription)"
        }
    }

    private func chooseExecutable(for kind: DiagramToolKind) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(kind.displayName) Executable"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        Task {
            let status = await DiagramToolRegistry.shared
                .setCustomExecutable(url, for: kind)
            apply(status, for: kind)
        }
    }

    private func apply(_ status: DiagramToolStatus, for kind: DiagramToolKind) {
        switch kind {
        case .mermaid:
            mermaidToolStatus = status
        case .d2:
            d2ToolStatus = status
        }
    }

    private func restoreDefaults() {
        let d2Defaults = D2RenderConfiguration.preview
        appearance = AppAppearance.system.rawValue
        markdownTheme = MarkdownPreviewTheme.diagramDown.rawValue
        mermaidLightTheme = MermaidPreviewTheme.default.rawValue
        mermaidDarkTheme = MermaidPreviewTheme.dark.rawValue
        zoom = PreviewZoom.defaultValue
        d2Layout = d2Defaults.layout.rawValue
        d2LightThemeID = d2Defaults.lightThemeID
        d2DarkThemeID = d2Defaults.darkThemeID
        d2Padding = d2Defaults.padding
        d2Sketch = d2Defaults.sketch
    }

    private struct D2Theme: Identifiable {
        let id: Int
        let name: String
    }

    private static let d2LightThemes = [
        D2Theme(id: 0, name: "Neutral default"),
        D2Theme(id: 1, name: "Neutral grey"),
        D2Theme(id: 3, name: "Flagship Terrastruct"),
        D2Theme(id: 4, name: "Cool classics"),
        D2Theme(id: 5, name: "Mixed berry blue"),
        D2Theme(id: 6, name: "Grape soda"),
        D2Theme(id: 100, name: "Vanilla nitro cola"),
        D2Theme(id: 101, name: "Orange creamsicle"),
        D2Theme(id: 102, name: "Shirley temple"),
        D2Theme(id: 103, name: "Earth tones"),
        D2Theme(id: 104, name: "Everglade green"),
        D2Theme(id: 105, name: "Buttered toast"),
    ]

    private static let d2DarkThemes = [
        D2Theme(id: 200, name: "Dark mauve"),
        D2Theme(id: 201, name: "Dark flagship"),
    ]
}
