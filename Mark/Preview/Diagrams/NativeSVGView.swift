//
//  NativeSVGView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

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
