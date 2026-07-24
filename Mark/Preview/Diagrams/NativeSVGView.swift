//
//  NativeSVGView.swift
//  DiagramDown
//

import SVGView
import SwiftUI

struct NativeSVGView: View {
    let document: SVGDocument

    var body: some View {
        SVGView(data: Data(document.sanitizedXML.utf8))
            .aspectRatio(
                document.intrinsicSize.width / max(document.intrinsicSize.height, 1),
                contentMode: .fit
            )
            .accessibilityLabel("Rendered diagram")
    }
}
