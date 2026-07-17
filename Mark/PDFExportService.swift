//
//  PDFExportService.swift
//  DiagramDown
//

import CoreGraphics
import Foundation

enum PDFExportError: LocalizedError {
    case invalidDocumentDimensions
    case invalidPDF

    var errorDescription: String? {
        switch self {
        case .invalidDocumentDimensions:
            "The preview reported an invalid document size."
        case .invalidPDF:
            "WebKit returned an invalid or empty PDF."
        }
    }
}

enum PDFExportService {
    static func validate(_ data: Data) throws {
        guard data.count > 8,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              document.numberOfPages > 0,
              let firstPage = document.page(at: 1) else {
            throw PDFExportError.invalidPDF
        }

        let bounds = firstPage.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            throw PDFExportError.invalidPDF
        }
    }

    static func paginate(_ data: Data) throws -> Data {
        guard let provider = CGDataProvider(data: data as CFData),
              let sourceDocument = CGPDFDocument(provider),
              let sourcePage = sourceDocument.page(at: 1) else {
            throw PDFExportError.invalidPDF
        }

        let sourceBounds = sourcePage.getBoxRect(.mediaBox)
        guard sourceBounds.width > 0, sourceBounds.height > 0 else {
            throw PDFExportError.invalidPDF
        }

        let pageBounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let margin: CGFloat = 36
        let printableWidth = pageBounds.width - (margin * 2)
        let printableHeight = pageBounds.height - (margin * 2)
        let scale = printableWidth / sourceBounds.width
        let sourceSliceHeight = printableHeight / scale
        let pageCount = max(Int(ceil(sourceBounds.height / sourceSliceHeight)), 1)

        let output = NSMutableData()
        var outputMediaBox = pageBounds
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(
                consumer: consumer,
                mediaBox: &outputMediaBox,
                nil
              ) else {
            throw PDFExportError.invalidPDF
        }

        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            context.clip(to: CGRect(
                x: margin,
                y: margin,
                width: printableWidth,
                height: printableHeight
            ))
            context.translateBy(x: margin, y: pageBounds.height - margin)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(
                x: -sourceBounds.minX,
                y: -sourceBounds.maxY + (CGFloat(pageIndex) * sourceSliceHeight)
            )
            context.drawPDFPage(sourcePage)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()

        let result = output as Data
        try validate(result)
        return result
    }
}
