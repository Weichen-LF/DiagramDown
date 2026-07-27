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
    @State private var viewerPreferredSize = CGSize(width: 720, height: 520)
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
                        viewerPreferredSize = Self.preferredViewerSize()
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

    private static func preferredViewerSize() -> CGSize {
        let parent = NSApp.keyWindow?.frame.size
            ?? NSApp.mainWindow?.frame.size
            ?? CGSize(width: 1_120, height: 720)
        return CGSize(
            width: max(720, parent.width * 0.9),
            height: max(520, parent.height * 0.9)
        )
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
        let request = diagramRequest

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
        .frame(
            minWidth: 480,
            idealWidth: preferredSize.width,
            minHeight: 360,
            idealHeight: preferredSize.height
        )
        .background(
            ResizableSheetWindowConfigurator(
                initialSize: preferredSize,
                minimumSize: CGSize(width: 480, height: 360)
            )
        )
    }
}

private struct ResizableSheetWindowConfigurator: NSViewRepresentable {
    let initialSize: CGSize
    let minimumSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(
                view,
                initialSize: initialSize,
                minimumSize: minimumSize
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.configureIfNeeded(
                nsView,
                initialSize: initialSize,
                minimumSize: minimumSize
            )
        }
    }

    final class Coordinator {
        private var didConfigure = false

        @MainActor
        func configureIfNeeded(
            _ view: NSView,
            initialSize: CGSize,
            minimumSize: CGSize
        ) {
            guard !didConfigure, let window = view.window else {
                return
            }
            didConfigure = true
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(
                width: minimumSize.width,
                height: minimumSize.height
            )
            window.setContentSize(
                NSSize(
                    width: max(initialSize.width, minimumSize.width),
                    height: max(initialSize.height, minimumSize.height)
                )
            )
        }
    }
}
