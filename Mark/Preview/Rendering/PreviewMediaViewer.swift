//
//  PreviewMediaViewer.swift
//  DiagramDown
//

import AppKit
import SwiftUI

enum PreviewMediaViewerSizing {
    static let defaultSize = CGSize(width: 960, height: 640)
    static let contentPadding: CGFloat = 24
    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 4

    static func preferredSize() -> CGSize {
        let parent = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentLayoutRect.size
            ?? CGSize(width: 1_120, height: 720)
        return CGSize(
            width: max(defaultSize.width, parent.width * 0.96),
            height: max(defaultSize.height, parent.height * 0.96)
        )
    }

    /// Scale that fits content into the viewport without upscaling past 1×.
    static func fitZoom(
        contentSize: CGSize,
        viewportSize: CGSize
    ) -> CGFloat {
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }
        let contentWidth = max(contentSize.width, 1)
        let contentHeight = max(contentSize.height, 1)
        let availableWidth = max(viewportSize.width - contentPadding * 2, 1)
        let availableHeight = max(viewportSize.height - contentPadding * 2, 1)
        let scale = min(availableWidth / contentWidth, availableHeight / contentHeight)
        return min(max(min(scale, 1), minimumZoom), maximumZoom)
    }
}

struct PreviewMediaViewerChrome<Content: View>: View {
    let title: String
    let preferredSize: CGSize
    let background: Color
    let contentSize: CGSize
    @ViewBuilder let content: (_ zoom: CGFloat) -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1
    @State private var viewportSize = CGSize.zero

    var body: some View {
        ZStack {
            // Establish the sheet's ideal size for `.fitted` presentation sizing.
            // ScrollView content alone is often much smaller than the parent window.
            Color.clear
                .frame(width: preferredSize.width, height: preferredSize.height)

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button("Fit") {
                        zoom = PreviewMediaViewerSizing.fitZoom(
                            contentSize: contentSize,
                            viewportSize: viewportSize
                        )
                        gestureStartZoom = zoom
                    }
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()

                Divider()

                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        content(zoom)
                            .padding(PreviewMediaViewerSizing.contentPadding)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(background)
                    .onAppear {
                        viewportSize = proxy.size
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        viewportSize = newSize
                    }
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                zoom = min(
                                    max(
                                        gestureStartZoom * value.magnification,
                                        PreviewMediaViewerSizing.minimumZoom
                                    ),
                                    PreviewMediaViewerSizing.maximumZoom
                                )
                            }
                            .onEnded { _ in
                                gestureStartZoom = zoom
                            }
                    )
                }
            }
        }
        .frame(
            minWidth: 640,
            idealWidth: preferredSize.width,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: preferredSize.height,
            maxHeight: .infinity
        )
        .presentationSizing(.fitted)
    }
}

struct PreviewImageViewerView: View {
    let image: NSImage
    let title: String
    let preferredSize: CGSize
    let background: Color

    private var imageSize: CGSize {
        let size = image.size
        return CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    var body: some View {
        PreviewMediaViewerChrome(
            title: title,
            preferredSize: preferredSize,
            background: background,
            contentSize: imageSize
        ) { zoom in
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(
                    width: max(imageSize.width * zoom, 100),
                    height: max(imageSize.height * zoom, 100)
                )
        }
    }
}
