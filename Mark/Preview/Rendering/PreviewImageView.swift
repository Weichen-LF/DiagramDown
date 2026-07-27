//
//  PreviewImageView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct PreviewImageView: View {
    let image: PreviewImage
    let documentURL: URL?
    let workspaceRootURL: URL
    let theme: PreviewTheme
    let metrics: PreviewMetrics

    @State private var loadedImage: NSImage?
    @State private var failure: String?
    @State private var showsViewer = false
    @State private var viewerPreferredSize = CGSize(width: 960, height: 640)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let loadedImage {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 7 * metrics.zoom))
                        .accessibilityLabel(image.alt.isEmpty ? "Image" : image.alt)
                } else if let failure {
                    Label(failure, systemImage: "photo.badge.exclamationmark")
                        .font(.system(size: metrics.bodyFontSize))
                        .foregroundStyle(theme.secondaryText)
                        .padding(metrics.codeInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.subtleBackground)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 64 * metrics.zoom)
                }
            }

            if loadedImage != nil {
                Button {
                    viewerPreferredSize = PreviewMediaViewerSizing.preferredSize()
                    showsViewer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
                .help("Open Image Preview")
            }
        }
        .task(id: requestID) {
            await load()
        }
        .sheet(isPresented: $showsViewer) {
            if let loadedImage {
                PreviewImageViewerView(
                    image: loadedImage,
                    title: image.alt.isEmpty ? "Image" : image.alt,
                    preferredSize: viewerPreferredSize,
                    background: theme.background
                )
            }
        }
    }

    private var requestID: String {
        "\(workspaceRootURL.path):\(documentURL?.path ?? ""):\(image.source)"
    }

    @MainActor
    private func load() async {
        loadedImage = nil
        failure = nil

        do {
            let image = image
            let documentURL = documentURL
            let workspaceRootURL = workspaceRootURL
            let data = try await Task.detached(priority: .utility) {
                try PreviewImageResolver.data(
                    for: image,
                    documentURL: documentURL,
                    workspaceRootURL: workspaceRootURL
                )
            }.value
            guard let decoded = NSImage(data: data) else {
                failure = "The image format is unsupported."
                return
            }
            loadedImage = decoded
        } catch {
            failure = error.localizedDescription
        }
    }
}
