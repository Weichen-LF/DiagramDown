//
//  MarkdownFormattingService.swift
//  DiagramDown
//

import Foundation
import JavaScriptCore

enum MarkdownFormattingError: LocalizedError {
    case runtimeMissing
    case runtimeFailed
    case invalidResult
    case inputTooLarge
    case documentChanged

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "The bundled Markdown formatter is missing."
        case .runtimeFailed:
            "The Markdown formatter could not be loaded."
        case .invalidResult:
            "The Markdown formatter returned an invalid result."
        case .inputTooLarge:
            "Documents larger than 4 MB cannot be formatted."
        case .documentChanged:
            "The document changed while formatting. No changes were applied."
        }
    }
}

@MainActor
final class MarkdownFormattingService {
    static let shared = MarkdownFormattingService()

    private let maximumInputBytes = 4 * 1_024 * 1_024
    private let context: JSContext?
    private var runtimeError: Error?

    private init() {
        guard let context = JSContext() else {
            self.context = nil
            runtimeError = MarkdownFormattingError.runtimeFailed
            return
        }
        self.context = context

        context.exceptionHandler = { [weak self] _, exception in
            guard let exception else { return }
            self?.runtimeError = NSError(
                domain: "DiagramDown.MarkdownFormatter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: exception.toString() ?? "JavaScript error"]
            )
        }

        do {
            // The formatter runtime is distributed as a browser-oriented bundle.
            // JavaScriptCore exposes globalThis but does not create browser aliases.
            context.evaluateScript("var window = globalThis; var self = globalThis;")
            if let runtimeError {
                throw runtimeError
            }

            for name in Self.runtimeScriptNames {
                guard let url = Self.runtimeURL(for: name) else {
                    throw MarkdownFormattingError.runtimeMissing
                }
                let script = try String(contentsOf: url, encoding: .utf8)
                context.evaluateScript(script, withSourceURL: url)
                if let runtimeError {
                    throw runtimeError
                }
            }
            guard context
                .objectForKeyedSubscript("formatterRuntime")?
                .objectForKeyedSubscript("formatMarkdown")?
                .isObject == true else {
                throw MarkdownFormattingError.runtimeFailed
            }
        } catch {
            runtimeError = error
        }
    }

    func format(_ source: String) async throws -> String {
        guard source.utf8.count <= maximumInputBytes else {
            throw MarkdownFormattingError.inputTooLarge
        }
        guard runtimeError == nil,
              let formatter = context?
                .objectForKeyedSubscript("formatterRuntime")?
                .objectForKeyedSubscript("formatMarkdown"),
              let promise = formatter.call(withArguments: [source]) else {
            throw runtimeError ?? MarkdownFormattingError.runtimeFailed
        }

        var formatted = try await string(from: promise)
        formatted = try await D2RenderService.shared.formatFencedBlocks(in: formatted)
        return formatted
    }

    private func string(from promise: JSValue) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let success: @convention(block) (JSValue) -> Void = { value in
                guard let result = value.toString() else {
                    continuation.resume(throwing: MarkdownFormattingError.invalidResult)
                    return
                }
                continuation.resume(returning: result)
            }
            let failure: @convention(block) (JSValue) -> Void = { value in
                continuation.resume(throwing: NSError(
                    domain: "DiagramDown.MarkdownFormatter",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            value.toString() ?? "Markdown formatting failed.",
                    ]
                ))
            }
            promise.invokeMethod("then", withArguments: [success, failure])
        }
    }

    private static let runtimeScriptNames = [
        "prettier",
        "markdown",
        "babel",
        "estree",
        "typescript",
        "html",
        "postcss",
        "yaml",
        "formatter",
    ]

    private static func runtimeURL(for name: String) -> URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: name,
            withExtension: "js",
            subdirectory: "Formatter"
        ) ?? bundle.url(
            forResource: name,
            withExtension: "js",
            subdirectory: "Resources/Formatter"
        ) ?? bundle.url(forResource: name, withExtension: "js")
    }
}
