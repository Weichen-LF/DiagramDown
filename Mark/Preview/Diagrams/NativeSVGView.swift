//
//  NativeSVGView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct NativeDiagramView: View {
    let document: DiagramDocument
    let background: Color

    var body: some View {
        switch document {
        case .svg(let svg):
            NativeSVGView(document: svg, background: background)
        case .raster(let raster):
            NativeRasterDiagramView(document: raster, background: background)
        }
    }
}

struct NativeSVGView: View {
    let document: SVGDocument
    let background: Color

    private var data: Data {
        Data(document.sanitizedXML.utf8)
    }

    var body: some View {
        Group {
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Label(
                    "The generated SVG could not be displayed.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
                .padding()
            }
        }
            .aspectRatio(
                document.intrinsicSize.width / max(document.intrinsicSize.height, 1),
                contentMode: .fit
            )
            .background(background)
            .accessibilityLabel("Rendered diagram")
    }
}

private struct NativeRasterDiagramView: View {
    let document: RasterDiagramDocument
    let background: Color

    var body: some View {
        Group {
            if let image = NSImage(data: document.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Label(
                    "The generated diagram image could not be displayed.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.red)
                .padding()
            }
        }
        .aspectRatio(
            document.intrinsicSize.width / max(document.intrinsicSize.height, 1),
            contentMode: .fit
        )
        .background(background)
        .accessibilityLabel("Rendered diagram")
    }
}
