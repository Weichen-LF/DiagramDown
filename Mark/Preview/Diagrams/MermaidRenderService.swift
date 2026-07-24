//
//  MermaidRenderService.swift
//  DiagramDown
//

import Foundation
import WebKit

nonisolated enum MermaidRenderError: LocalizedError, Sendable {
    case runtimeMissing
    case runtimeUnavailable
    case inputTooLarge
    case invalidResponse
    case outputTooLarge
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "The bundled Mermaid renderer is missing."
        case .runtimeUnavailable:
            "The Mermaid renderer could not be initialized."
        case .inputTooLarge:
            "The Mermaid source exceeds the 256 KB preview limit."
        case .invalidResponse:
            "Mermaid returned an invalid render result."
        case .outputTooLarge:
            "The generated Mermaid SVG exceeds the 8 MB limit."
        case .renderFailed(let message):
            message.isEmpty ? "Mermaid could not render this diagram." : message
        }
    }
}

actor MermaidRenderService {
    static let shared = MermaidRenderService()
    nonisolated static let rendererVersion = "bundled-runtime-v1"

    private var requestCounter: UInt64 = 0
    private let maximumInputBytes = 256 * 1_024
    private let maximumOutputBytes = 8 * 1_024 * 1_024

    func render(
        source: String,
        theme: MermaidPreviewTheme,
        appearance: String
    ) async throws -> String {
        try Task.checkCancellation()
        guard source.utf8.count <= maximumInputBytes else {
            throw MermaidRenderError.inputTooLarge
        }
        requestCounter &+= 1
        let requestID = "m-\(requestCounter)"

        do {
            let result = try await MermaidWebViewHost.shared.render(
                source: source,
                requestID: requestID,
                theme: theme.rawValue,
                appearance: appearance
            )
            try Task.checkCancellation()
            guard result.utf8.count <= maximumOutputBytes else {
                throw MermaidRenderError.outputTooLarge
            }
            return result
        } catch let error as MermaidRenderError {
            throw error
        } catch {
            let message = (error as NSError).localizedDescription
            throw MermaidRenderError.renderFailed(
                String(message.prefix(1_024))
            )
        }
    }
}

@MainActor
final class MermaidWebViewHost: NSObject {
    static let shared = MermaidWebViewHost()

    private let webView: WKWebView
    private var runtimeReady = false
    private var runtimeLoading = false
    private var readinessContinuations: [CheckedContinuation<Void, Error>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func render(
        source: String,
        requestID: String,
        theme: String,
        appearance: String
    ) async throws -> String {
        try await loadRuntime()
        let response = try await webView.callAsyncJavaScript(
            """
            return await window.mermaidRuntime.render(
                source,
                requestID,
                theme,
                appearance
            );
            """,
            arguments: [
                "source": source,
                "requestID": requestID,
                "theme": theme,
                "appearance": appearance,
            ],
            in: nil,
            contentWorld: .page
        )
        guard let payload = response as? [String: Any],
              payload["requestID"] as? String == requestID,
              let svg = payload["svg"] as? String,
              svg.range(of: "<svg", options: .caseInsensitive) != nil else {
            throw MermaidRenderError.invalidResponse
        }
        return svg
    }

    private func loadRuntime() async throws {
        if runtimeReady {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            readinessContinuations.append(continuation)
            guard !runtimeLoading else {
                return
            }
            guard let url = Self.runtimeURL else {
                finishLoading(with: .failure(MermaidRenderError.runtimeMissing))
                return
            }

            runtimeLoading = true
            webView.loadFileURL(
                url,
                allowingReadAccessTo: url.deletingLastPathComponent()
            )
        }
    }

    private func validateRuntime() {
        Task {
            do {
                let result = try await webView.callAsyncJavaScript(
                    "return typeof window.mermaidRuntime?.render === 'function';",
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                guard result as? Bool == true else {
                    throw MermaidRenderError.runtimeUnavailable
                }
                finishLoading(with: .success(()))
            } catch {
                finishLoading(with: .failure(error))
            }
        }
    }

    private func finishLoading(with result: Result<Void, Error>) {
        runtimeLoading = false
        runtimeReady = (try? result.get()) != nil
        let continuations = readinessContinuations
        readinessContinuations.removeAll()
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }

    private static var runtimeURL: URL? {
        let bundle = Bundle.main
        return bundle.url(
            forResource: "renderer",
            withExtension: "html",
            subdirectory: "MermaidRenderer"
        ) ?? bundle.url(
            forResource: "renderer",
            withExtension: "html",
            subdirectory: "Resources/MermaidRenderer"
        ) ?? bundle.url(
            forResource: "renderer",
            withExtension: "html"
        )
    }
}

extension MermaidWebViewHost: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        validateRuntime()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        finishLoading(with: .failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: Error
    ) {
        finishLoading(with: .failure(error))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        runtimeReady = false
        if runtimeLoading {
            finishLoading(with: .failure(MermaidRenderError.runtimeUnavailable))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(url.isFileURL || url.absoluteString == "about:blank" ? .allow : .cancel)
    }
}
