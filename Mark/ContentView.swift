//
//  ContentView.swift
//  DiagramDown
//
//  Created by Walt Wang on 2026-07-16.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument

    var body: some View {
        HSplitView {
            MarkdownEditorView(text: $document.text)
                .frame(minWidth: 320, idealWidth: 560)

            MarkdownPreviewView(markdown: document.text)
                .frame(minWidth: 320, idealWidth: 560)
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(MarkdownDocument()))
            .frame(width: 1_120, height: 720)
    }
}
