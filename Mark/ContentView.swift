//
//  ContentView.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
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
                editorScrollPosition: editorScrollPosition,
                onPreviewScroll: synchronizeEditor,
                onSourceLineSelected: selectSourceLine
            )
                .frame(minWidth: 320, idealWidth: 560)
        }
        .frame(minWidth: 720, minHeight: 420)
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
