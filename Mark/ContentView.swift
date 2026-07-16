//
//  ContentView.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

enum DocumentViewMode: String, CaseIterable, Identifiable {
    case editorOnly
    case editorAndPreview
    case previewOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editorOnly:
            "Editor Only"
        case .editorAndPreview:
            "Editor and Preview"
        case .previewOnly:
            "Preview Only"
        }
    }

    var systemImage: String {
        switch self {
        case .editorOnly:
            "chevron.left.forwardslash.chevron.right"
        case .editorAndPreview:
            "rectangle.split.2x1"
        case .previewOnly:
            "eye"
        }
    }

    var showsPreview: Bool {
        self != .editorOnly
    }
}

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @AppStorage(PreviewPreferences.appearanceKey) private var appearance =
        AppAppearance.system.rawValue
    @AppStorage(PreviewPreferences.markdownThemeKey) private var markdownTheme =
        MarkdownPreviewTheme.diagramDown.rawValue
    @AppStorage(PreviewPreferences.mermaidLightThemeKey) private var mermaidLightTheme =
        MermaidPreviewTheme.default.rawValue
    @AppStorage(PreviewPreferences.mermaidDarkThemeKey) private var mermaidDarkTheme =
        MermaidPreviewTheme.dark.rawValue
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
    @AppStorage(PreviewPreferences.zoomKey) private var previewZoom = PreviewZoom.defaultValue
    @SceneStorage("DocumentView.mode") private var storedViewMode =
        DocumentViewMode.editorAndPreview.rawValue
    @StateObject private var previewController = PreviewController()
    @State private var editorScrollPosition = ScrollSyncPosition.initial
    @State private var editorScrollTarget = ScrollSyncTarget.initial

    var body: some View {
        documentBody
        .frame(minWidth: 720, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("View Mode", selection: viewModeBinding) {
                    ForEach(DocumentViewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage)
                            .labelStyle(.iconOnly)
                            .help(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    previewZoom = PreviewZoom.clamped(previewZoom - PreviewZoom.step)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(
                    !activeViewMode.showsPreview
                        || PreviewZoom.clamped(previewZoom) <= PreviewZoom.minimum
                )

                Menu {
                    ForEach(PreviewZoom.menuValues, id: \.self) { value in
                        Button {
                            previewZoom = value
                        } label: {
                            if value == PreviewZoom.clamped(previewZoom) {
                                Label("\(value)%", systemImage: "checkmark")
                            } else {
                                Text("\(value)%")
                            }
                        }
                    }
                } label: {
                    Text("\(PreviewZoom.clamped(previewZoom))%")
                        .monospacedDigit()
                        .frame(minWidth: 42)
                }
                .help("Preview Zoom")
                .disabled(!activeViewMode.showsPreview)

                Button {
                    previewZoom = PreviewZoom.clamped(previewZoom + PreviewZoom.step)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(
                    !activeViewMode.showsPreview
                        || PreviewZoom.clamped(previewZoom) >= PreviewZoom.maximum
                )

                Button {
                    previewController.exportPDF()
                } label: {
                    Label("Export Preview as PDF", systemImage: "doc.richtext")
                }
                .help("Export Preview as PDF…")
                .disabled(!activeViewMode.showsPreview)
            }
        }
        .focusedSceneValue(
            \.previewExportPDFAction,
            activeViewMode.showsPreview
                ? PreviewExportPDFAction(perform: previewController.exportPDF)
                : nil
        )
    }

    @ViewBuilder
    private var documentBody: some View {
        switch activeViewMode {
        case .editorOnly:
            editorPane
        case .editorAndPreview:
            HSplitView {
                editorPane
                    .frame(minWidth: 320, idealWidth: 560)
                previewPane
                    .frame(minWidth: 320, idealWidth: 560)
            }
        case .previewOnly:
            previewPane
        }
    }

    private var editorPane: some View {
        MarkdownEditorView(
            text: $document.text,
            scrollPosition: $editorScrollPosition,
            scrollTarget: editorScrollTarget
        )
    }

    private var previewPane: some View {
        MarkdownPreviewView(
            markdown: document.text,
            configuration: previewConfiguration,
            zoom: PreviewZoom.clamped(previewZoom),
            documentBaseName: documentBaseName,
            previewController: previewController,
            editorScrollPosition: editorScrollPosition,
            onZoomChanged: { previewZoom = PreviewZoom.clamped($0) },
            onPreviewScroll: synchronizeEditor,
            onSourceLineSelected: selectSourceLine
        )
    }

    private var activeViewMode: DocumentViewMode {
        DocumentViewMode(rawValue: storedViewMode) ?? .editorAndPreview
    }

    private var viewModeBinding: Binding<DocumentViewMode> {
        Binding(
            get: { activeViewMode },
            set: { storedViewMode = $0.rawValue }
        )
    }

    private var documentBaseName: String {
        guard let fileURL else {
            return "Untitled"
        }
        return fileURL.deletingPathExtension().lastPathComponent
    }

    private var previewConfiguration: PreviewConfiguration {
        PreviewConfiguration(
            appearance: AppAppearance(rawValue: appearance) ?? .system,
            markdownTheme: MarkdownPreviewTheme(rawValue: markdownTheme) ?? .diagramDown,
            mermaidLightTheme: MermaidPreviewTheme(rawValue: mermaidLightTheme) ?? .default,
            mermaidDarkTheme: MermaidPreviewTheme(rawValue: mermaidDarkTheme) ?? .dark,
            d2: D2RenderConfiguration(
                layout: D2RenderConfiguration.Layout(rawValue: d2Layout) ?? .dagre,
                lightThemeID: d2LightThemeID,
                darkThemeID: d2DarkThemeID,
                padding: min(max(d2Padding, 0), 200),
                sketch: d2Sketch
            )
        )
    }

    private func selectSourceLine(_ sourceLine: Int) {
        editorScrollTarget = ScrollSyncTarget(
            sourceLine: Double(sourceLine),
            progress: editorScrollTarget.progress,
            usesProgressFallback: false,
            animated: true,
            generation: editorScrollTarget.generation &+ 1
        )
    }

    private func synchronizeEditor(
        _ sourceLine: Double,
        _ progress: Double,
        _ usesProgressFallback: Bool
    ) {
        editorScrollTarget = ScrollSyncTarget(
            sourceLine: sourceLine,
            progress: progress,
            usesProgressFallback: usesProgressFallback,
            animated: false,
            generation: editorScrollTarget.generation &+ 1
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(MarkdownDocument()), fileURL: nil)
            .frame(width: 1_120, height: 720)
    }
}
