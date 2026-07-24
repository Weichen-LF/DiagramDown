//
//  SVGDocument.swift
//  DiagramDown
//

import CoreGraphics
import Foundation

nonisolated struct SVGDocument: Hashable, Sendable {
    let sanitizedXML: String
    let intrinsicSize: CGSize
    let digest: String
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
