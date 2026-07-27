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
    @State private var showsViewer = false
    @State private var viewerPreferredSize = CGSize(width: 960, height: 640)
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
                        viewerPreferredSize = PreviewMediaViewerSizing.preferredSize()
                        showsViewer = true
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
        .sheet(isPresented: $showsViewer) {
            if let document = state.document {
                DiagramViewerView(
                    document: document,
                    title: kind == .mermaid ? "Mermaid Diagram" : "D2 Diagram",
                    theme: theme,
                    preferredSize: viewerPreferredSize
                )
            }
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
            blockID.rawValue,
            String(revision),
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
        if case .rendered = state {
            // Re-render after an already-visible diagram (theme/tool change).
        } else {
            state = .rendering
        }
        let request = diagramRequest
        let expectedBlockID = blockID
        let expectedRevision = revision

        do {
            let result = try await DiagramRenderCoordinator.shared.render(request)
            try Task.checkCancellation()
            guard result.blockID == expectedBlockID,
                  result.revision == expectedRevision,
                  blockID == expectedBlockID,
                  revision == expectedRevision else {
                return
            }
            state = .rendered(result.document)
        } catch is CancellationError {
            return
        } catch is DiagramToolResolutionError {
            guard blockID == expectedBlockID, revision == expectedRevision else {
                return
            }
            state = .unavailable
        } catch {
            guard blockID == expectedBlockID, revision == expectedRevision else {
                return
            }
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

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1

    var body: some View {
        ZStack {
            // Establish the sheet's ideal size for `.fitted` presentation sizing.
            // ScrollView content alone is often much smaller than the parent window.
            Color.clear
                .frame(width: preferredSize.width, height: preferredSize.height)

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Button("Fit") { zoom = 1 }
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()

                Divider()

                ScrollView([.horizontal, .vertical]) {
                    NativeDiagramView(
                        document: document,
                        background: theme.background
                    )
                        .frame(
                            width: max(document.intrinsicSize.width * zoom, 100),
                            height: max(document.intrinsicSize.height * zoom, 100)
                        )
                        .padding(24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = min(max(gestureStartZoom * value.magnification, 0.25), 4)
                        }
                        .onEnded { _ in
                            gestureStartZoom = zoom
                        }
                )
            }
        }
        .frame(
            minWidth: 640,
            idealWidth: preferredSize.width,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: preferredSize.height,
            maxHeight: .infinity
        )
        .presentationSizing(.fitted)
    }
}
