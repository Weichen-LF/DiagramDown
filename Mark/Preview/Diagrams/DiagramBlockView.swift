//
//  DiagramBlockView.swift
//  DiagramDown
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum DiagramBlockState {
    case idle
    case rendering
    case rendered(DiagramDocument)
    case unavailable
    case failed(message: String)

    var document: DiagramDocument? {
        guard case .rendered(let document) = self else { return nil }
        return document
    }

    var isRendered: Bool {
        if case .rendered = self { return true }
        return false
    }
}

private struct DiagramViewerPresentation: Identifiable {
    let id = UUID()
    let document: DiagramDocument
    let preferredSize: CGSize
}

struct DiagramBlockView: View {
    let blockID: PreviewBlockID
    let revision: UInt64
    let sourceRange: PreviewSourceRange
    let kind: DiagramKind
    let source: String
    let configuration: PreviewConfiguration
    let theme: PreviewTheme
    let metrics: PreviewMetrics
    let documentBaseName: String
    let onSourceLineSelected: (Int) -> Void

    @State private var state = DiagramBlockState.idle
    @State private var viewerPresentation: DiagramViewerPresentation?
    @AppStorage(DiagramToolRegistry.revisionPreferenceKey) private var toolRevision = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            diagramContent
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    onSourceLineSelected(sourceRange.startLine)
                }

            if let document = state.document {
                HStack(spacing: 6) {
                    Button {
                        viewerPresentation = DiagramViewerPresentation(
                            document: document,
                            preferredSize: PreviewMediaViewerSizing.preferredSize()
                        )
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .help("Open Diagram Preview")

                    Button {
                        export(document)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Export SVG…")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(8)
            }
        }
        .padding(8 * metrics.zoom)
        .background(theme.subtleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9 * metrics.zoom))
        .overlay {
            RoundedRectangle(cornerRadius: 9 * metrics.zoom)
                .stroke(theme.border, lineWidth: 1)
        }
        .task(id: requestID) {
            await render()
        }
        .sheet(item: $viewerPresentation) { presentation in
            DiagramViewerView(
                document: presentation.document,
                title: kind == .mermaid ? "Mermaid Diagram" : "D2 Diagram",
                theme: theme,
                preferredSize: presentation.preferredSize
            )
        }
    }

    @ViewBuilder
    private var diagramContent: some View {
        switch state {
        case .idle, .rendering:
            ZStack(alignment: .topTrailing) {
                CodeBlockView(
                    source: source,
                    language: nil,
                    rawLanguage: kind.rawValue,
                    theme: theme,
                    metrics: metrics
                )
                if case .rendering = state {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .help("Rendering diagram…")
                }
            }

        case .rendered(let document):
            NativeDiagramView(
                document: document,
                background: theme.background
            )
                .frame(maxHeight: metrics.diagramMaximumHeight)

        case .unavailable:
            VStack(alignment: .leading, spacing: 8) {
                CodeBlockView(
                    source: source,
                    language: nil,
                    rawLanguage: kind.rawValue,
                    theme: theme,
                    metrics: metrics
                )
                SettingsLink {
                    Label("Configure Diagram Tools", systemImage: "wrench.and.screwdriver")
                }
                .controlSize(.small)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                CodeBlockView(
                    source: source,
                    language: nil,
                    rawLanguage: kind.rawValue,
                    theme: theme,
                    metrics: metrics
                )
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: metrics.bodyFontSize))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var requestID: String {
        [
            kind.rawValue,
            MarkdownParserService.digest(source),
            theme.id,
            configuration.d2.cacheDescriptor,
            String(toolRevision),
        ].joined(separator: ":")
    }

    @MainActor
    private func render() async {
        // Keep the fenced source visible while the CLI work runs off the main
        // actor path through DiagramRenderCoordinator / ExternalProcessRunner.
        // Avoid flashing back to source while re-rendering an already-visible diagram.
        if !state.isRendered {
            state = .rendering
        }
        let request = diagramRequest

        do {
            let result = try await DiagramRenderCoordinator.shared.render(request)
            try Task.checkCancellation()
            state = .rendered(result.document)
        } catch is CancellationError {
            return
        } catch is DiagramToolResolutionError {
            state = .unavailable
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private var diagramRequest: DiagramRenderRequest {
        let dark = theme.id.hasSuffix("-dark")
        return DiagramRenderRequest(
            blockID: blockID,
            revision: revision,
            kind: kind,
            source: source,
            configuration: DiagramConfiguration(
                mermaidTheme: dark
                    ? configuration.mermaidDarkTheme
                    : configuration.mermaidLightTheme,
                appearance: dark ? "dark" : "light",
                d2: configuration.d2
            )
        )
    }

    @MainActor
    private func export(_ document: DiagramDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName

        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            Task { @MainActor in
                await writeSVGExport(document, to: url)
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }

    @MainActor
    private func writeSVGExport(_ document: DiagramDocument, to url: URL) async {
        do {
            let svg: String
            switch kind {
            case .mermaid:
                svg = try await DiagramRenderCoordinator.shared.renderMermaidSVG(
                    diagramRequest
                )
            case .d2:
                guard case .svg(let svgDocument) = document else {
                    throw DiagramRasterError.invalidImage
                }
                svg = svgDocument.sanitizedXML
            }
            try Data(svg.utf8).write(to: url, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private var suggestedFileName: String {
        let safeBase = documentBaseName
            .map { "/:".contains($0) ? "-" : $0 }
        let base = String(safeBase)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Untitled" : String(base.prefix(96))
        return "\(name)-\(kind.rawValue)-line-\(sourceRange.startLine).svg"
    }
}

private struct DiagramViewerView: View {
    let document: DiagramDocument
    let title: String
    let theme: PreviewTheme
    let preferredSize: CGSize

    var body: some View {
        PreviewMediaViewerChrome(
            title: title,
            preferredSize: preferredSize,
            background: theme.background,
            contentSize: document.intrinsicSize
        ) { zoom in
            NativeDiagramView(
                document: document,
                background: theme.background
            )
            .frame(
                width: max(document.intrinsicSize.width * zoom, 100),
                height: max(document.intrinsicSize.height * zoom, 100)
            )
        }
    }
}
