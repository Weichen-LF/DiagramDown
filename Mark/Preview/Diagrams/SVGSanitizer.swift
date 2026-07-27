//
//  SVGSanitizer.swift
//  DiagramDown
//

import CoreGraphics
import CryptoKit
import Foundation

actor SVGSanitizer {
    static let shared = SVGSanitizer()

    private let maximumBytes = 8 * 1_024 * 1_024
    private let maximumDimension: CGFloat = 20_000
    private let maximumDepth = 128
    private let maximumElements = 50_000
    private let maximumAttributeLength = 256 * 1_024
    private let forbiddenElements: Set<String> = [
        "script", "foreignobject", "iframe", "object", "embed",
        "audio", "video", "canvas",
    ]

    func sanitize(_ source: String) throws -> SVGDocument {
        let data = Data(source.utf8)
        guard data.count <= maximumBytes else {
            throw SVGSanitizerError.oversized
        }
        let lowercasedPrefix = source.prefix(8_192).lowercased()
        guard !lowercasedPrefix.contains("<!doctype"),
              !lowercasedPrefix.contains("<!entity") else {
            throw SVGSanitizerError.prohibitedXML
        }

        let document: XMLDocument
        do {
            document = try XMLDocument(
                data: data,
                options: [.nodeLoadExternalEntitiesNever, .nodePreserveAll]
            )
        } catch {
            throw SVGSanitizerError.malformed
        }

        guard let root = document.rootElement(),
              root.localName?.lowercased() == "svg" else {
            throw SVGSanitizerError.invalidRoot
        }

        var elementCount = 0
        try sanitize(element: root, depth: 0, elementCount: &elementCount)
        let intrinsicSize = try size(of: root)
        removeCanvasBackgroundRects(from: root, canvasSize: intrinsicSize)
        document.characterEncoding = "UTF-8"
        let xml = document.xmlString(options: [.nodeCompactEmptyElement])
        guard xml.utf8.count <= maximumBytes else {
            throw SVGSanitizerError.oversized
        }

        return SVGDocument(
            sanitizedXML: xml,
            intrinsicSize: intrinsicSize,
            digest: MarkdownParserService.digest(xml)
        )
    }

    /// D2 and mmdr bake a full-canvas background rect into the SVG.
    ///
    /// AppKit's SVG renderer paints `fill="transparent"` / `#00000000` as opaque
    /// black, so the canvas rect must be removed rather than recolored.
    private func removeCanvasBackgroundRects(
        from element: XMLElement,
        canvasSize: CGSize
    ) {
        let viewBox = parsedViewBox(of: element) ?? CGRect(
            origin: .zero,
            size: canvasSize
        )

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else {
                continue
            }
            let name = (childElement.localName ?? childElement.name ?? "").lowercased()
            if name == "svg" {
                let nestedSize = (try? size(of: childElement)) ?? canvasSize
                removeCanvasBackgroundRects(from: childElement, canvasSize: nestedSize)
                continue
            }
            guard name == "rect",
                  isCanvasBackgroundRect(childElement, viewBox: viewBox) else {
                continue
            }
            childElement.detach()
        }
    }

    private func parsedViewBox(of element: XMLElement) -> CGRect? {
        guard let viewBox = element.attribute(forName: "viewBox")?.stringValue else {
            return nil
        }
        let values = viewBox
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .compactMap { Double($0) }
        guard values.count == 4,
              values[2] > 0,
              values[3] > 0 else {
            return nil
        }
        return CGRect(
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3]
        )
    }

    private func isCanvasBackgroundRect(
        _ element: XMLElement,
        viewBox: CGRect
    ) -> Bool {
        guard let width = numericValue(element.attribute(forName: "width")?.stringValue),
              let height = numericValue(element.attribute(forName: "height")?.stringValue),
              width >= viewBox.width * 0.98,
              height >= viewBox.height * 0.98 else {
            return false
        }

        let x = numericValue(element.attribute(forName: "x")?.stringValue) ?? 0
        let y = numericValue(element.attribute(forName: "y")?.stringValue) ?? 0
        // Match the SVG viewBox origin so D2 pad offsets (e.g. x=-41) still count.
        guard abs(x - viewBox.minX) <= max(viewBox.width * 0.02, 3),
              abs(y - viewBox.minY) <= max(viewBox.height * 0.02, 3) else {
            return false
        }

        if let strokeWidth = numericValue(
            element.attribute(forName: "stroke-width")?.stringValue
        ), strokeWidth > 0 {
            return false
        }
        let style = (element.attribute(forName: "style")?.stringValue ?? "")
            .lowercased()
        if style.contains("stroke-width") {
            let strokeFromStyle = style
                .split(separator: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { $0.hasPrefix("stroke-width") }
            if let strokeFromStyle,
               let value = numericValue(
                strokeFromStyle.split(separator: ":").last.map(String.init)
               ),
               value > 0 {
                return false
            }
        }

        let className = (element.attribute(forName: "class")?.stringValue ?? "")
            .lowercased()
        if className.contains("fill-n7") {
            return true
        }

        let fill = (element.attribute(forName: "fill")?.stringValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if fill.hasPrefix("url(") {
            return false
        }
        // Keep intentional "none" absences; remove opaque and AppKit-broken fills.
        switch fill {
        case "", "none":
            return false
        case "transparent", "#00000000", "rgba(0,0,0,0)", "rgba(0, 0, 0, 0)":
            return true
        case "white", "#fff", "#ffffff":
            return true
        default:
            // Solid theme canvas fills from D2/mmdr (often #FFFFFF / theme N7).
            return !fill.contains("gradient")
        }
    }

    private func sanitize(
        element: XMLElement,
        depth: Int,
        elementCount: inout Int
    ) throws {
        guard depth <= maximumDepth else {
            throw SVGSanitizerError.excessiveComplexity
        }
        elementCount += 1
        guard elementCount <= maximumElements else {
            throw SVGSanitizerError.excessiveComplexity
        }

        for attribute in element.attributes ?? [] {
            let name = (attribute.localName ?? attribute.name ?? "").lowercased()
            let value = attribute.stringValue ?? ""
            if name.hasPrefix("on")
                || value.utf8.count > maximumAttributeLength
                || !isAllowedAttribute(name: name, value: value, element: element) {
                if let originalName = attribute.name {
                    element.removeAttribute(forName: originalName)
                }
            }
        }

        for child in element.children ?? [] {
            guard let childElement = child as? XMLElement else {
                continue
            }
            let name = (childElement.localName ?? childElement.name ?? "").lowercased()
            if forbiddenElements.contains(name) {
                childElement.detach()
                continue
            }
            try sanitize(
                element: childElement,
                depth: depth + 1,
                elementCount: &elementCount
            )
        }
    }

    private func isAllowedAttribute(
        name: String,
        value: String,
        element: XMLElement
    ) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if name == "style" {
            if normalized.contains("javascript:")
                || normalized.contains("@import")
                || normalized.contains("expression(") {
                return false
            }
            let externalURL = try? NSRegularExpression(
                pattern: #"url\(\s*['"]?(?!#|data:image/)"#,
                options: [.caseInsensitive]
            )
            let range = NSRange(location: 0, length: value.utf16.count)
            return externalURL?.firstMatch(in: value, range: range) == nil
        }

        guard ["href", "xlink:href", "src"].contains(name) else {
            return !normalized.contains("javascript:")
        }
        if normalized.hasPrefix("#") || normalized.hasPrefix("data:image/") {
            return true
        }

        let elementName = (element.localName ?? element.name ?? "").lowercased()
        guard elementName == "a",
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private func size(of root: XMLElement) throws -> CGSize {
        if let viewBox = root.attribute(forName: "viewBox")?.stringValue {
            let values = viewBox
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .compactMap { Double($0) }
            if values.count == 4 {
                return try validatedSize(
                    width: CGFloat(values[2]),
                    height: CGFloat(values[3])
                )
            }
        }

        let width = numericValue(root.attribute(forName: "width")?.stringValue)
        let height = numericValue(root.attribute(forName: "height")?.stringValue)
        if let width, let height {
            return try validatedSize(width: width, height: height)
        }
        return CGSize(width: 800, height: 600)
    }

    private func numericValue(_ value: String?) -> CGFloat? {
        guard let value else {
            return nil
        }
        let match = value.prefix {
            $0.isNumber || $0 == "." || $0 == "-" || $0 == "+"
        }
        guard let number = Double(match), number.isFinite else {
            return nil
        }
        return CGFloat(number)
    }

    private func validatedSize(width: CGFloat, height: CGFloat) throws -> CGSize {
        guard width.isFinite,
              height.isFinite,
              width > 0,
              height > 0,
              width <= maximumDimension,
              height <= maximumDimension else {
            throw SVGSanitizerError.invalidDimensions
        }
        return CGSize(width: width, height: height)
    }
}
