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
    case rendered(SVGDocument)
    case unavailable
    case failed(message: String)

    var document: SVGDocument? {
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
                    theme: theme
                )
            }
        }
    }

    @ViewBuilder
    private var diagramContent: some View {
        switch state {
        case .idle:
            ProgressView()
                .controlSize(.small)
                .frame(minHeight: 100 * metrics.zoom)

        case .rendering:
            ProgressView()
                .controlSize(.small)
                .frame(minHeight: 100 * metrics.zoom)

        case .rendered(let document):
            NativeSVGView(
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
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: metrics.bodyFontSize))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
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
        state = .rendering
        let dark = theme.id.hasSuffix("-dark")
        let request = DiagramRenderRequest(
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

        do {
            let result = try await DiagramRenderCoordinator.shared.render(request)
            try Task.checkCancellation()
            guard result.blockID == blockID, result.revision == revision else {
                return
            }
            state = .rendered(result.document)
        } catch is CancellationError {
            return
        } catch is DiagramToolResolutionError {
            state = .unavailable
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    @MainActor
    private func export(_ document: SVGDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName

        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            do {
                try Data(document.sanitizedXML.utf8).write(
                    to: url,
                    options: .atomic
                )
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }

        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
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
    let document: SVGDocument
    let title: String
    let theme: PreviewTheme

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var gestureStartZoom: CGFloat = 1

    var body: some View {
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
                NativeSVGView(
                    document: document,
                    background: theme.background
                )
                    .frame(
                        width: max(document.intrinsicSize.width * zoom, 100),
                        height: max(document.intrinsicSize.height * zoom, 100)
                    )
                    .padding(24)
            }
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
        .frame(minWidth: 720, minHeight: 520)
    }
}
