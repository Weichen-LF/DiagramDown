//
//  SVGDocument.swift
//  DiagramDown
//

import CoreGraphics
import Foundation
import ImageIO

nonisolated struct SVGDocument: Hashable, Sendable {
    let sanitizedXML: String
    let intrinsicSize: CGSize
    let digest: String
}

nonisolated struct RasterDiagramDocument: Hashable, Sendable {
    let data: Data
    let intrinsicSize: CGSize
    let digest: String

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            throw DiagramRasterError.invalidImage
        }
        self.data = data
        intrinsicSize = CGSize(
            width: width.doubleValue,
            height: height.doubleValue
        )
        digest = MarkdownParserService.digest(data.base64EncodedString())
    }
}

nonisolated enum DiagramDocument: Hashable, Sendable {
    case svg(SVGDocument)
    case raster(RasterDiagramDocument)

    var intrinsicSize: CGSize {
        switch self {
        case .svg(let document):
            document.intrinsicSize
        case .raster(let document):
            document.intrinsicSize
        }
    }

    var digest: String {
        switch self {
        case .svg(let document):
            document.digest
        case .raster(let document):
            document.digest
        }
    }

    var byteCount: Int {
        switch self {
        case .svg(let document):
            document.sanitizedXML.utf8.count
        case .raster(let document):
            document.data.count
        }
    }
}

nonisolated enum DiagramRasterError: LocalizedError, Sendable {
    case invalidImage

    var errorDescription: String? {
        "The generated diagram image is invalid."
    }
}

nonisolated enum SVGSanitizerError: Equatable, LocalizedError, Sendable {
    case oversized
    case prohibitedXML
    case malformed
    case invalidRoot
    case excessiveComplexity
    case invalidDimensions

    var errorDescription: String? {
        switch self {
        case .oversized:
            "The generated SVG exceeds the 8 MB limit."
        case .prohibitedXML:
            "The SVG contains a prohibited document type or entity."
        case .malformed:
            "The generated SVG is malformed."
        case .invalidRoot:
            "The generated document is not an SVG."
        case .excessiveComplexity:
            "The generated SVG is too complex to display safely."
        case .invalidDimensions:
            "The generated SVG has invalid dimensions."
        }
    }
}
