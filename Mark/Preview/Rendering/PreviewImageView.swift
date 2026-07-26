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

    var body: some View {
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
        .task(id: requestID) {
            await load()
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
            let data = try await Task.detached {
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
