//
//  MarkdownPreviewView.swift
//  DiagramDown
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let configuration: PreviewConfiguration
    let zoom: Int
    let documentBaseName: String
    let previewController: PreviewController
    let editorScrollPosition: ScrollSyncPosition
    let onPreviewScroll: (Double, Double, Bool) -> Void
    let onSourceLineSelected: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            documentBaseName: documentBaseName,
            onPreviewScroll: onPreviewScroll,
            onSourceLineSelected: onSourceLineSelected
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "d2")
        configuration.userContentController.add(context.coordinator, name: "exportSVG")
        configuration.userContentController.add(context.coordinator, name: "scrollSync")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        Self.applyZoom(zoom, to: webView)
        Self.applyAppearance(self.configuration.appearance, to: webView)

        #if DEBUG
        webView.isInspectable = true
        #endif

        context.coordinator.attach(
            to: webView,
            initialMarkdown: markdown,
            configuration: self.configuration,
            previewController: previewController
        )

        guard let previewURL = Self.previewPageURL else {
            context.coordinator.loadMissingRuntimePage()
            return webView
        }

        context.coordinator.loadRuntime(at: previewURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSourceLineSelected = onSourceLineSelected
        context.coordinator.onPreviewScroll = onPreviewScroll
        context.coordinator.documentBaseName = documentBaseName
        Self.applyZoom(zoom, to: webView)
        Self.applyAppearance(configuration.appearance, to: webView)
        context.coordinator.scheduleRender(markdown, configuration: configuration)
        context.coordinator.scheduleScrollSync(editorScrollPosition)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelPendingRender()
        coordinator.cancelD2Rendering()
        coordinator.cancelScrollSync()
        coordinator.detachPreviewController()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "d2")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "exportSVG")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scrollSync")
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

    private static func applyAppearance(
        _ appearance: AppAppearance,
        to webView: WKWebView
    ) {
        switch appearance {
        case .system:
            webView.appearance = nil
        case .light:
            webView.appearance = NSAppearance(named: .aqua)
        case .dark:
            webView.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private static func applyZoom(_ zoom: Int, to webView: WKWebView) {
        let pageZoom = CGFloat(PreviewZoom.clamped(zoom)) / 100
        if abs(webView.pageZoom - pageZoom) > 0.001 {
            webView.pageZoom = pageZoom
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
            category: "MarkdownPreview"
        )

        private weak var webView: WKWebView?
        private var renderTask: Task<Void, Never>?
        private var d2RenderTask: Task<Void, Never>?
        private var scrollTask: Task<Void, Never>?
        private var pendingMarkdown = ""
        private var pendingConfiguration: PreviewConfiguration
        private var appliedConfiguration: PreviewConfiguration
        private var pendingScrollPosition = ScrollSyncPosition.initial
        private var appliedScrollGeneration: UInt64 = 0
        private var revision: UInt64 = 0
        private var runtimeAvailable = false
        private var runtimeReady = false
        private var savePanelPresented = false
        private var pdfExportInProgress = false
        private weak var previewController: PreviewController?
        var documentBaseName: String
        var onPreviewScroll: (Double, Double, Bool) -> Void
        var onSourceLineSelected: (Int) -> Void

        init(
            configuration: PreviewConfiguration,
            documentBaseName: String,
            onPreviewScroll: @escaping (Double, Double, Bool) -> Void,
            onSourceLineSelected: @escaping (Int) -> Void
        ) {
            pendingConfiguration = configuration
            appliedConfiguration = configuration
            self.documentBaseName = documentBaseName
            self.onPreviewScroll = onPreviewScroll
            self.onSourceLineSelected = onSourceLineSelected
        }

        func attach(
            to webView: WKWebView,
            initialMarkdown: String,
            configuration: PreviewConfiguration,
            previewController: PreviewController
        ) {
            self.webView = webView
            self.previewController = previewController
            previewController.coordinator = self
            pendingMarkdown = initialMarkdown
            pendingConfiguration = configuration
        }

        func detachPreviewController() {
            if previewController?.coordinator === self {
                previewController?.coordinator = nil
            }
            previewController = nil
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

        func scheduleRender(
            _ markdown: String,
            configuration: PreviewConfiguration
        ) {
            guard markdown != pendingMarkdown
                    || configuration != pendingConfiguration else {
                return
            }

            pendingMarkdown = markdown
            pendingConfiguration = configuration
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

        func scheduleScrollSync(_ position: ScrollSyncPosition) {
            pendingScrollPosition = position
            guard runtimeReady,
                  position.generation != 0,
                  position.generation != appliedScrollGeneration else {
                return
            }

            scrollTask?.cancel()
            scrollTask = Task { [weak self] in
                await self?.applyPendingScrollPosition()
            }
        }

        func cancelScrollSync() {
            scrollTask?.cancel()
            scrollTask = nil
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
            cancelScrollSync()
            Self.logger.error("Markdown preview web content process terminated; reloading runtime")
            webView.reload()
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.frameInfo.isMainFrame else {
                return
            }

            switch message.name {
            case "d2":
                handleD2Message(message)
            case "exportSVG":
                handleExportSVGMessage(message)
            case "scrollSync":
                handleScrollSyncMessage(message)
            default:
                break
            }
        }

        private func handleExportSVGMessage(_ message: WKScriptMessage) {
            guard !savePanelPresented,
                  !pdfExportInProgress,
                  let payload = message.body as? [String: Any],
                  let blockID = payload["blockID"] as? String,
                  let kind = payload["kind"] as? String,
                  let svg = payload["svg"] as? String,
                  ["mermaid", "d2"].contains(kind),
                  blockID.count <= 128,
                  blockID.range(
                      of: #"^(mermaid|d2)-[0-9a-f]{16}-[0-9]+$"#,
                      options: .regularExpression
                  ) != nil,
                  svg.utf8.count <= 8 * 1_024 * 1_024,
                  svg.range(of: "<svg", options: .caseInsensitive) != nil,
                  svg.range(of: "</svg>", options: .caseInsensitive) != nil else {
                return
            }

            let sourceLine = (payload["sourceLine"] as? NSNumber)?.intValue
            let lineSuffix = sourceLine.map { "-line-\(max($0, 1))" } ?? ""
            let kindSuffix = safeDocumentBaseName.caseInsensitiveCompare(kind) == .orderedSame
                ? ""
                : "-\(kind)"
            let suggestedName = "\(safeDocumentBaseName)\(kindSuffix)\(lineSuffix).svg"
            let exportSVG = svg.hasPrefix("<?xml")
                ? svg
                : "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\(svg)"
            let data = Data(exportSVG.utf8)

            presentSavePanel(
                suggestedName: suggestedName,
                contentType: .svg
            ) { [weak self] url in
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    self?.showExportError("The SVG could not be saved.", error: error)
                }
            }
        }

        func exportPreviewPDF() {
            guard !savePanelPresented, !pdfExportInProgress else {
                return
            }
            guard runtimeReady, let webView else {
                showAlert(
                    title: "Preview Not Ready",
                    message: "Wait for the Markdown preview to finish loading, then try again."
                )
                return
            }

            pdfExportInProgress = true
            Task { [weak self, weak webView] in
                guard let self, let webView else {
                    self?.pdfExportInProgress = false
                    return
                }

                do {
                    let result = try await webView.callAsyncJavaScript(
                        "return await window.previewRuntime.prepareForPDFExport();",
                        arguments: [:],
                        in: nil,
                        contentWorld: .page
                    )
                    guard let readiness = result as? [String: Any],
                          readiness["ready"] as? Bool == true else {
                        let message = (result as? [String: Any])?["message"] as? String
                            ?? "Some diagrams are still rendering. Try exporting again."
                        pdfExportInProgress = false
                        showAlert(title: "Preview Not Ready", message: message)
                        return
                    }

                    presentSavePanel(
                        suggestedName: "\(safeDocumentBaseName).pdf",
                        contentType: .pdf
                    ) { [weak self, weak webView] url in
                        guard let self, let webView else {
                            return
                        }
                        exportPDF(from: webView, to: url)
                    }
                } catch {
                    pdfExportInProgress = false
                    showExportError("The preview could not be prepared for PDF export.", error: error)
                }
            }
        }

        private func exportPDF(from webView: WKWebView, to url: URL) {
            let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            printInfo.jobDisposition = .save
            printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.topMargin = 36
            printInfo.bottomMargin = 36
            printInfo.leftMargin = 36
            printInfo.rightMargin = 36

            let operation = webView.printOperation(with: printInfo)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = true
            let succeeded = operation.run()
            pdfExportInProgress = false

            if !succeeded || !FileManager.default.fileExists(atPath: url.path) {
                showAlert(
                    title: "PDF Export Failed",
                    message: "The Markdown preview could not be written as a PDF."
                )
            }
        }

        private func presentSavePanel(
            suggestedName: String,
            contentType: UTType,
            completion: @escaping (URL) -> Void
        ) {
            guard !savePanelPresented else {
                return
            }

            savePanelPresented = true
            let panel = NSSavePanel()
            panel.allowedContentTypes = [contentType]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = suggestedName

            let handleResponse: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else {
                    return
                }
                savePanelPresented = false
                guard response == .OK, let url = panel.url else {
                    if contentType == .pdf {
                        pdfExportInProgress = false
                    }
                    return
                }
                completion(url)
            }

            if let window = webView?.window {
                panel.beginSheetModal(for: window, completionHandler: handleResponse)
            } else {
                handleResponse(panel.runModal())
            }
        }

        private var safeDocumentBaseName: String {
            let sanitized = documentBaseName
                .map { "/:".contains($0) ? "-" : $0 }
            let name = String(sanitized)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Untitled" : String(name.prefix(96))
        }

        private func showExportError(_ message: String, error: Error) {
            showAlert(title: "Export Failed", message: "\(message)\n\n\(error.localizedDescription)")
        }

        private func showAlert(title: String, message: String) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            if let window = webView?.window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }

        private func handleD2Message(_ message: WKScriptMessage) {
            guard
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

            renderD2Blocks(
                blocks,
                revision: requestedRevision,
                configuration: appliedConfiguration.d2
            )
        }

        private func handleScrollSyncMessage(_ message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any],
                  let kind = payload["kind"] as? String,
                  let lineNumber = payload["sourceLine"] as? NSNumber else {
                return
            }

            let sourceLine = lineNumber.doubleValue
            guard sourceLine.isFinite,
                  sourceLine >= 1,
                  sourceLine <= 10_000_000 else {
                return
            }

            switch kind {
            case "selection":
                onSourceLineSelected(Int(sourceLine.rounded()))
            case "previewScroll":
                guard let progressNumber = payload["progress"] as? NSNumber else {
                    return
                }
                let progress = progressNumber.doubleValue
                guard progress.isFinite else {
                    return
                }
                let usesProgressFallback = payload["usesProgressFallback"] as? Bool ?? false
                onPreviewScroll(
                    sourceLine,
                    min(max(progress, 0), 1),
                    usesProgressFallback
                )
            default:
                return
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
            let currentConfiguration = pendingConfiguration
            appliedConfiguration = currentConfiguration
            cancelD2Rendering()

            Task {
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "return window.previewRuntime.renderMarkdown(markdown, revision, d2ConfigurationID, appearance, markdownTheme, mermaidLightTheme, mermaidDarkTheme);",
                        arguments: [
                            "markdown": pendingMarkdown,
                            "revision": currentRevision,
                            "d2ConfigurationID": currentConfiguration.d2.cacheDescriptor,
                            "appearance": currentConfiguration.appearance.rawValue,
                            "markdownTheme": currentConfiguration.markdownTheme.rawValue,
                            "mermaidLightTheme": currentConfiguration.mermaidLightTheme.rawValue,
                            "mermaidDarkTheme": currentConfiguration.mermaidDarkTheme.rawValue,
                        ],
                        in: nil,
                        contentWorld: .page
                    )
                    await self.applyPendingScrollPosition(force: true)
                } catch {
                    self.logJavaScriptError("Markdown preview update failed", error: error)
                }
            }
        }

        private func showRuntimeFailurePage() {
            runtimeAvailable = false
            runtimeReady = false
            cancelD2Rendering()
            cancelScrollSync()

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

        private func applyPendingScrollPosition(force: Bool = false) async {
            let position = pendingScrollPosition
            guard runtimeReady,
                  position.generation != 0,
                  force || position.generation != appliedScrollGeneration,
                  let webView else {
                return
            }

            do {
                _ = try await webView.callAsyncJavaScript(
                    "return window.previewRuntime.scrollToSourceLine(sourceLine, progress);",
                    arguments: [
                        "sourceLine": position.sourceLine,
                        "progress": position.progress,
                    ],
                    in: nil,
                    contentWorld: .page
                )
                appliedScrollGeneration = position.generation
            } catch {
                logJavaScriptError("Preview scroll synchronization failed", error: error)
            }
        }

        private func renderD2Blocks(
            _ blocks: [D2BlockRequest],
            revision: UInt64,
            configuration: D2RenderConfiguration
        ) {
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
                        let result = try await D2RenderService.shared.render(
                            source: block.source,
                            configuration: configuration
                        )
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
