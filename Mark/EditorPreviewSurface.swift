//
//  EditorPreviewSurface.swift
//  DiagramDown
//

import Combine
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

@MainActor
final class EditorPreviewSessionState: ObservableObject {
    let previewController = PreviewController()
    let editorController = MarkdownEditorController()
    @Published var editorScrollPosition = ScrollSyncPosition.initial
    @Published var editorScrollTarget = ScrollSyncTarget.initial
}

struct EditorPreviewSurface: View {
    @Binding var text: String
    let fileURL: URL?
    let workspaceRootURL: URL
    @Binding var storedViewMode: String
    @ObservedObject var session: EditorPreviewSessionState

    @AppStorage(PreviewPreferences.appearanceKey) private var appearance =
        AppAppearance.system.rawValue
    @AppStorage(PreviewPreferences.markdownThemeKey) private var markdownTheme =
        MarkdownPreviewTheme.diagramDown.rawValue
    @AppStorage(PreviewPreferences.mermaidRendererKey) private var mermaidRenderer =
        MermaidRendererEngine.mmdr.rawValue
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
                        session.previewController.exportPDF()
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
                    ? PreviewExportPDFAction(perform: session.previewController.exportPDF)
                    : nil
            )
            .focusedSceneValue(
                \.formatDocumentAction,
                activeViewMode == .previewOnly
                    ? nil
                    : FormatDocumentAction(perform: session.editorController.formatDocument)
            )
            .focusedSceneValue(
                \.markdownEditMenuAction,
                activeViewMode == .previewOnly
                    ? nil
                    : MarkdownEditMenuAction(
                        perform: session.editorController.perform
                    )
            )
            .focusedSceneValue(
                \.insertMarkdownImageAction,
                activeViewMode == .previewOnly
                    ? nil
                    : InsertMarkdownImageAction {
                        session.editorController.insertImage(
                            documentURL: fileURL,
                            workspaceRootURL: workspaceRootURL
                        )
                    }
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
            text: $text,
            scrollPosition: $session.editorScrollPosition,
            scrollTarget: session.editorScrollTarget,
            editorController: session.editorController
        )
    }

    private var previewPane: some View {
        NativeMarkdownPreviewView(
            markdown: text,
            configuration: previewConfiguration,
            zoom: PreviewZoom.clamped(previewZoom),
            fileURL: fileURL,
            workspaceRootURL: workspaceRootURL,
            documentBaseName: documentBaseName,
            previewController: session.previewController,
            editorScrollPosition: session.editorScrollPosition,
            onZoomChanged: { previewZoom = PreviewZoom.clamped($0) },
            onPreviewScroll: synchronizeEditor,
            onSourceLineSelected: selectSourceLine
        )
    }

    private var activeViewMode: DocumentViewMode {
        DocumentViewMode(rawValue: storedViewMode) ?? .previewOnly
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
            mermaidRenderer: MermaidRendererEngine(rawValue: mermaidRenderer) ?? .mmdr,
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
        session.editorScrollTarget = ScrollSyncTarget(
            sourceLine: Double(sourceLine),
            progress: session.editorScrollTarget.progress,
            usesProgressFallback: false,
            animated: true,
            generation: session.editorScrollTarget.generation &+ 1
        )
    }

    private func synchronizeEditor(
        _ sourceLine: Double,
        _ progress: Double,
        _ usesProgressFallback: Bool
    ) {
        session.editorScrollTarget = ScrollSyncTarget(
            sourceLine: sourceLine,
            progress: progress,
            usesProgressFallback: usesProgressFallback,
            animated: false,
            generation: session.editorScrollTarget.generation &+ 1
        )
    }
}
