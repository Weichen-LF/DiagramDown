//
//  ContentView.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @AppStorage(D2PreviewPreferences.layoutKey) private var d2Layout =
        D2RenderConfiguration.Layout.dagre.rawValue
    @AppStorage(D2PreviewPreferences.lightThemeIDKey) private var d2LightThemeID =
        D2RenderConfiguration.preview.lightThemeID
    @AppStorage(D2PreviewPreferences.darkThemeIDKey) private var d2DarkThemeID =
        D2RenderConfiguration.preview.darkThemeID
    @AppStorage(D2PreviewPreferences.paddingKey) private var d2Padding =
        D2RenderConfiguration.preview.padding
    @AppStorage(D2PreviewPreferences.sketchKey) private var d2Sketch =
        D2RenderConfiguration.preview.sketch
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
                d2Configuration: d2Configuration,
                editorScrollPosition: editorScrollPosition,
                onPreviewScroll: synchronizeEditor,
                onSourceLineSelected: selectSourceLine
            )
                .frame(minWidth: 320, idealWidth: 560)
        }
        .frame(minWidth: 720, minHeight: 420)
    }

    private var d2Configuration: D2RenderConfiguration {
        D2RenderConfiguration(
            layout: D2RenderConfiguration.Layout(rawValue: d2Layout) ?? .dagre,
            lightThemeID: d2LightThemeID,
            darkThemeID: d2DarkThemeID,
            padding: min(max(d2Padding, 0), 200),
            sketch: d2Sketch
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
        ContentView(document: .constant(MarkdownDocument()))
            .frame(width: 1_120, height: 720)
    }
}
