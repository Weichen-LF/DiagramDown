//
//  MarkdownPreviewFacade.swift
//  DiagramDown
//

import SwiftUI

struct MarkdownPreviewView: View {
    let markdown: String
    let configuration: PreviewConfiguration
    let zoom: Int
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let previewController: PreviewController
    let editorScrollPosition: ScrollSyncPosition
    let onZoomChanged: (Int) -> Void
    let onPreviewScroll: (Double, Double, Bool) -> Void
    let onSourceLineSelected: (Int) -> Void

    var body: some View {
        NativeMarkdownPreviewView(
            markdown: markdown,
            configuration: configuration,
            zoom: zoom,
            fileURL: fileURL,
            workspaceRootURL: workspaceRootURL,
            documentBaseName: documentBaseName,
            previewController: previewController,
            editorScrollPosition: editorScrollPosition,
            onZoomChanged: onZoomChanged,
            onPreviewScroll: onPreviewScroll,
            onSourceLineSelected: onSourceLineSelected
        )
    }
}
