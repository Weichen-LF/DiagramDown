//
//  MarkdownPreviewView.swift
//  DiagramDown
//

import AppKit
import OSLog
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear

        #if DEBUG
        webView.isInspectable = true
        #endif

        context.coordinator.attach(to: webView, initialMarkdown: markdown)

        guard let previewURL = Self.previewPageURL else {
            context.coordinator.loadMissingRuntimePage()
            return webView
        }

        context.coordinator.loadRuntime(at: previewURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.scheduleRender(markdown)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelPendingRender()
        webView.navigationDelegate = nil
    }

    private static var previewPageURL: URL? {
        let bundle = Bundle.main

        return bundle.url(
            forResource: "preview",
            withExtension: "html",
            subdirectory: "Preview"
        ) ?? bundle.url(
            forResource: "preview",
            withExtension: "html",
            subdirectory: "Resources/Preview"
        ) ?? bundle.url(
            forResource: "preview",
            withExtension: "html"
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
            category: "MarkdownPreview"
        )

        private weak var webView: WKWebView?
        private var renderTask: Task<Void, Never>?
        private var pendingMarkdown = ""
        private var revision: UInt64 = 0
        private var runtimeAvailable = false
        private var runtimeReady = false

        func attach(to webView: WKWebView, initialMarkdown: String) {
            self.webView = webView
            pendingMarkdown = initialMarkdown
        }

        func loadRuntime(at previewURL: URL) {
            runtimeAvailable = true
            webView?.loadFileURL(
                previewURL,
                allowingReadAccessTo: previewURL.deletingLastPathComponent()
            )
        }

        func loadMissingRuntimePage() {
            let fallback = """
            <!doctype html>
            <html>
            <body style="font: 14px -apple-system; padding: 24px; color: #b42318">
              Markdown preview resources are missing from the application bundle.
            </body>
            </html>
            """
            webView?.loadHTMLString(fallback, baseURL: nil)
        }

        func scheduleRender(_ markdown: String) {
            pendingMarkdown = markdown
            guard runtimeReady else {
                return
            }

            renderTask?.cancel()
            renderTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(150))
                } catch {
                    return
                }

                guard !Task.isCancelled else {
                    return
                }

                self?.renderPendingMarkdown()
            }
        }

        func cancelPendingRender() {
            renderTask?.cancel()
            renderTask = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            guard runtimeAvailable else {
                return
            }

            Task { [weak self, weak webView] in
                guard let self, let webView else {
                    return
                }

                do {
                    let result = try await webView.callAsyncJavaScript(
                        "return typeof window.previewRuntime?.renderMarkdown === 'function';",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )

                    guard result as? Bool == true else {
                        showRuntimeFailurePage()
                        return
                    }

                    runtimeReady = true
                    renderPendingMarkdown()
                } catch {
                    logJavaScriptError("Markdown preview runtime check failed", error: error)
                    showRuntimeFailurePage()
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            runtimeReady = false
            Self.logger.error("Markdown preview web content process terminated; reloading runtime")
            webView.reload()
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

            if navigationAction.navigationType == .linkActivated {
                if let scheme = url.scheme?.lowercased(),
                   ["http", "https", "mailto"].contains(scheme) {
                    NSWorkspace.shared.open(url)
                }

                decisionHandler(.cancel)
                return
            }

            if url.isFileURL || url.absoluteString == "about:blank" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        private func renderPendingMarkdown() {
            guard runtimeReady, let webView else {
                return
            }

            revision &+= 1
            let currentRevision = revision

            Task {
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "return window.previewRuntime.renderMarkdown(markdown, revision);",
                        arguments: [
                            "markdown": pendingMarkdown,
                            "revision": currentRevision,
                        ],
                        in: nil,
                        contentWorld: .page
                    )
                } catch {
                    self.logJavaScriptError("Markdown preview update failed", error: error)
                }
            }
        }

        private func showRuntimeFailurePage() {
            runtimeAvailable = false
            runtimeReady = false

            let fallback = """
            <!doctype html>
            <html>
            <body style="font: 14px -apple-system; padding: 24px; color: #b42318">
              Markdown preview runtime failed to load. Rebuild the application and try again.
            </body>
            </html>
            """
            webView?.loadHTMLString(fallback, baseURL: nil)
        }

        private func logJavaScriptError(_ message: String, error: Error) {
            let nsError = error as NSError
            Self.logger.error(
                "\(message, privacy: .public) [\(nsError.domain, privacy: .public) \(nsError.code)]: \(String(describing: error), privacy: .public)"
            )
        }
    }
}
