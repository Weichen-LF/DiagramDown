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
    @SceneStorage("DocumentView.mode") private var storedViewMode =
        DocumentViewMode.editorAndPreview.rawValue
    @StateObject private var editorPreviewSession = EditorPreviewSessionState()

    var body: some View {
        EditorPreviewSurface(
            text: $document.text,
            fileURL: fileURL,
            storedViewMode: $storedViewMode,
            session: editorPreviewSession
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(MarkdownDocument()), fileURL: nil)
            .frame(width: 1_120, height: 720)
    }
}
