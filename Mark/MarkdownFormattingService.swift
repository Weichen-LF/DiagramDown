//
//  MarkdownFormattingService.swift
//  DiagramDown
//

import Foundation
import Markdown

nonisolated enum MarkdownFormattingError: LocalizedError, Sendable {
    case inputTooLarge
    case documentChanged

    var errorDescription: String? {
        switch self {
        case .inputTooLarge:
            "Documents larger than 4 MB cannot be formatted."
        case .documentChanged:
            "The document changed while formatting. No changes were applied."
        }
    }
}

actor MarkdownFormattingService {
    static let shared = MarkdownFormattingService()

    private let maximumInputBytes = 4 * 1_024 * 1_024

    func format(_ source: String) async throws -> String {
        guard source.utf8.count <= maximumInputBytes else {
            throw MarkdownFormattingError.inputTooLarge
        }

        let document = Document(parsing: source)
        var formatted = document.format()
        formatted = try await D2RenderService.shared.formatFencedBlocks(in: formatted)
        return formatted
    }
}
