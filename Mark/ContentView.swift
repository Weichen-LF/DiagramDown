//
//  ContentView.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

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
    @StateObject private var previewController = PreviewController()
    @State private var editorScrollPosition = ScrollSyncPosition.initial
    @State private var editorScrollTarget = ScrollSyncTarget.initial

    var body: some View {
        HSplitView {
            MarkdownEditorView(
                text: $document.text,
                scrollPosition: $editorScrollPosition,
                scrollTarget: editorScrollTarget
            )
                .frame(minWidth: 320, idealWidth: 560)

            MarkdownPreviewView(
                markdown: document.text,
                configuration: previewConfiguration,
                zoom: PreviewZoom.clamped(previewZoom),
                documentBaseName: documentBaseName,
                previewController: previewController,
                editorScrollPosition: editorScrollPosition,
                onPreviewScroll: synchronizeEditor,
                onSourceLineSelected: selectSourceLine
            )
                .frame(minWidth: 320, idealWidth: 560)
        }
        .frame(minWidth: 720, minHeight: 420)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    previewZoom = PreviewZoom.clamped(previewZoom - PreviewZoom.step)
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(PreviewZoom.clamped(previewZoom) <= PreviewZoom.minimum)

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

                Button {
                    previewZoom = PreviewZoom.clamped(previewZoom + PreviewZoom.step)
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(PreviewZoom.clamped(previewZoom) >= PreviewZoom.maximum)

                Button {
                    previewController.exportPDF()
                } label: {
                    Label("Export Preview as PDF", systemImage: "doc.richtext")
                }
                .help("Export Preview as PDF…")
            }
        }
        .focusedSceneValue(
            \.previewExportPDFAction,
            PreviewExportPDFAction(perform: previewController.exportPDF)
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
