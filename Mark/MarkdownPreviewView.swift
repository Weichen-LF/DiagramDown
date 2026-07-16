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
        configuration.userContentController.add(context.coordinator, name: "d2")

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
        coordinator.cancelD2Rendering()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "d2")
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
            category: "MarkdownPreview"
        )

        private weak var webView: WKWebView?
        private var renderTask: Task<Void, Never>?
        private var d2RenderTask: Task<Void, Never>?
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

        func cancelD2Rendering() {
            d2RenderTask?.cancel()
            d2RenderTask = nil
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
            cancelD2Rendering()
            Self.logger.error("Markdown preview web content process terminated; reloading runtime")
            webView.reload()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "d2",
                  message.frameInfo.isMainFrame,
                  let payload = message.body as? [String: Any],
                  let revisionNumber = payload["revision"] as? NSNumber,
                  let rawBlocks = payload["blocks"] as? [[String: Any]] else {
                return
            }

            let requestedRevision = revisionNumber.uint64Value
            guard requestedRevision == revision, rawBlocks.count <= 64 else {
                return
            }

            let blocks = rawBlocks.compactMap { rawBlock -> D2BlockRequest? in
                guard let blockID = rawBlock["id"] as? String,
                      let source = rawBlock["source"] as? String,
                      blockID.count <= 128,
                      blockID.range(
                          of: #"^d2-[0-9a-f]{16}-[0-9]+$"#,
                          options: .regularExpression
                      ) != nil else {
                    return nil
                }

                return D2BlockRequest(id: blockID, source: source)
            }

            guard blocks.count == rawBlocks.count else {
                return
            }

            renderD2Blocks(blocks, revision: requestedRevision)
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
            cancelD2Rendering()

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
            cancelD2Rendering()

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

        private func renderD2Blocks(_ blocks: [D2BlockRequest], revision: UInt64) {
            cancelD2Rendering()

            d2RenderTask = Task { [weak self] in
                guard let self else {
                    return
                }

                for block in blocks {
                    guard !Task.isCancelled, revision == self.revision else {
                        return
                    }

                    do {
                        let result = try await D2RenderService.shared.render(source: block.source)
                        try Task.checkCancellation()
                        guard revision == self.revision else {
                            return
                        }
                        try await applyD2Result(
                            blockID: block.id,
                            revision: revision,
                            svg: result.svg
                        )
                    } catch is CancellationError {
                        return
                    } catch D2RenderError.cancelled {
                        return
                    } catch {
                        guard !Task.isCancelled, revision == self.revision else {
                            return
                        }
                        let description = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        await applyD2Error(
                            blockID: block.id,
                            revision: revision,
                            message: String(description.prefix(8_192))
                        )
                    }
                }
            }
        }

        private func applyD2Result(
            blockID: String,
            revision: UInt64,
            svg: String
        ) async throws {
            guard runtimeReady, revision == self.revision, let webView else {
                return
            }

            _ = try await webView.callAsyncJavaScript(
                "return window.previewRuntime.applyD2Result(blockID, revision, svg);",
                arguments: [
                    "blockID": blockID,
                    "revision": revision,
                    "svg": svg,
                ],
                in: nil,
                contentWorld: .page
            )
        }

        private func applyD2Error(
            blockID: String,
            revision: UInt64,
            message: String
        ) async {
            guard runtimeReady, revision == self.revision, let webView else {
                return
            }

            do {
                _ = try await webView.callAsyncJavaScript(
                    "return window.previewRuntime.applyD2Error(blockID, revision, message);",
                    arguments: [
                        "blockID": blockID,
                        "revision": revision,
                        "message": message,
                    ],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                logJavaScriptError("D2 preview error update failed", error: error)
            }
        }

        private struct D2BlockRequest: Sendable {
            let id: String
            let source: String
        }
    }
}
