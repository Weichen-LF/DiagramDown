//
//  MarkdownFormattingService.swift
//  DiagramDown
//

import AppKit
import WebKit

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
final class MarkdownFormattingService: NSObject, WKNavigationDelegate {
    static let shared = MarkdownFormattingService()

    private let maximumInputBytes = 4 * 1_024 * 1_024
    private let webView: WKWebView
    private var runtimeReady = false
    private var runtimeError: Error?
    private var readinessWaiters: [CheckedContinuation<Void, Error>] = []

    override private init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self

        guard let runtimeURL = Self.runtimeURL else {
            runtimeError = MarkdownFormattingError.runtimeMissing
            return
        }
        webView.loadFileURL(
            runtimeURL,
            allowingReadAccessTo: runtimeURL.deletingLastPathComponent()
        )
    }

    func format(_ source: String) async throws -> String {
        guard source.utf8.count <= maximumInputBytes else {
            throw MarkdownFormattingError.inputTooLarge
        }

        try await waitUntilReady()
        let result = try await webView.callAsyncJavaScript(
            "return await window.formatterRuntime.formatMarkdown(source);",
            arguments: ["source": source],
            in: nil,
            contentWorld: .page
        )
        guard var formatted = result as? String else {
            throw MarkdownFormattingError.invalidResult
        }
        formatted = try await D2RenderService.shared.formatFencedBlocks(in: formatted)
        return formatted
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        runtimeReady = true
        resumeWaiters(with: .success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        failRuntime(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        failRuntime(with: error)
    }

    private func waitUntilReady() async throws {
        if runtimeReady {
            return
        }
        if let runtimeError {
            throw runtimeError
        }
        try await withCheckedThrowingContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }

    private func failRuntime(with error: Error) {
        runtimeError = error
        resumeWaiters(with: .failure(MarkdownFormattingError.runtimeFailed))
    }

    private func resumeWaiters(with result: Result<Void, Error>) {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private static var runtimeURL: URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: "formatter",
            withExtension: "html",
            subdirectory: "Formatter"
        ) ?? bundle.url(
            forResource: "formatter",
            withExtension: "html",
            subdirectory: "Resources/Formatter"
        ) ?? bundle.url(forResource: "formatter", withExtension: "html")
    }
}
