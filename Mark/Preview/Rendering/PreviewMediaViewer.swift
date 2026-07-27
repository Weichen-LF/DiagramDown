//
//  PreviewMediaViewer.swift
//  DiagramDown
//

import AppKit
import SwiftUI

enum PreviewMediaViewerSizing {
    static func preferredSize() -> CGSize {
        let parent = (NSApp.keyWindow ?? NSApp.mainWindow)?.contentLayoutRect.size
            ?? CGSize(width: 1_120, height: 720)
        return CGSize(
            width: max(960, parent.width * 0.96),
            height: max(640, parent.height * 0.96)
        )
    }
}

struct PreviewImageViewerView: View {
    let image: NSImage
    let title: String
    let preferredSize: CGSize
    let background: Color

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1

    private var imageSize: CGSize {
        let size = image.size
        return CGSize(
            width: max(size.width, 1),
            height: max(size.height, 1)
        )
    }

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: preferredSize.width, height: preferredSize.height)

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button("Fit") { zoom = 1 }
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()

                Divider()

                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(
                            width: max(imageSize.width * zoom, 100),
                            height: max(imageSize.height * zoom, 100)
                        )
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(gestureStartZoom * value.magnification, 0.25), 4)
                        }
                        .onEnded { _ in
                            gestureStartZoom = zoom
                        }
                )
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
