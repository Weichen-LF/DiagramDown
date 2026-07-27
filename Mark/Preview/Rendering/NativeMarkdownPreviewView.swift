//
//  NativeMarkdownPreviewView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct NativeMarkdownPreviewView: View {
    let markdown: String
    let configuration: PreviewConfiguration
    let zoom: Int
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let previewController: PreviewController
    let editorScrollPosition: ScrollSyncPosition
    let onZoomChanged: (Int) -> Void
    let onPreviewScroll: (Double, Double, Bool) -> Void
    let onSourceLineSelected: (Int) -> Void

    @StateObject private var model = NativePreviewModel()

    var body: some View {
        NativePreviewDocumentView(
            document: model.document,
            parseError: model.parseError,
            isParsing: model.isParsing,
            configuration: configuration,
            zoom: zoom,
            fileURL: fileURL,
            workspaceRootURL: workspaceRootURL,
            documentBaseName: documentBaseName,
            previewController: previewController,
            editorScrollPosition: editorScrollPosition,
            onZoomChanged: onZoomChanged,
            onPreviewScroll: onPreviewScroll,
            onSourceLineSelected: onSourceLineSelected
        )
        .task(id: markdown) {
            await model.update(source: markdown)
        }
        .preferredColorScheme(configuration.appearance.colorScheme)
    }
}

private struct NativePreviewDocumentView: View {
    let document: PreviewDocument
    let parseError: String?
    let isParsing: Bool
    let configuration: PreviewConfiguration
    let zoom: Int
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let previewController: PreviewController
    let editorScrollPosition: ScrollSyncPosition
    let onZoomChanged: (Int) -> Void
    let onPreviewScroll: (Double, Double, Bool) -> Void
    let onSourceLineSelected: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var geometries: [PreviewBlockGeometry] = []
    @State private var appliedEditorGeneration: UInt64 = 0
    @State private var suppressPreviewReporting = false
    @State private var gestureStartZoom = PreviewZoom.defaultValue

    private var theme: PreviewTheme {
        .resolved(configuration: configuration, colorScheme: colorScheme)
    }

    private var metrics: PreviewMetrics {
        PreviewMetrics(zoom: CGFloat(PreviewZoom.clamped(zoom)) / 100)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.blockSpacing) {
                    if document.blocks.isEmpty {
                        Text("Start writing to see the preview.")
                            .foregroundStyle(theme.secondaryText)
                            .font(.system(size: metrics.bodyFontSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(document.blocks) { block in
                        PreviewBlockView(
                            block: block,
                            revision: document.revision,
                            configuration: configuration,
                            theme: theme,
                            metrics: metrics,
                            fileURL: fileURL,
                            workspaceRootURL: workspaceRootURL,
                            documentBaseName: documentBaseName,
                            onSourceLineSelected: onSourceLineSelected
                        )
                        .id(block.id)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: PreviewBlockGeometryPreferenceKey.self,
                                    value: [
                                        PreviewBlockGeometry(
                                            blockID: block.id,
                                            sourceRange: block.sourceRange,
                                            minY: geometry.frame(
                                                in: .named("native-preview-scroll")
                                            ).minY,
                                            maxY: geometry.frame(
                                                in: .named("native-preview-scroll")
                                            ).maxY
                                        ),
                                    ]
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, metrics.documentHorizontalInset)
                .padding(.vertical, metrics.documentVerticalInset)
                .frame(maxWidth: 920 * metrics.zoom, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .coordinateSpace(name: "native-preview-scroll")
            .background(theme.background)
            .textSelection(.enabled)
            .overlay(alignment: .top) {
                statusBanner
            }
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard SafePreviewURL.link(url.absoluteString) != nil else {
                        return .discarded
                    }
                    NSWorkspace.shared.open(url)
                    return .handled
                }
            )
            .onPreferenceChange(PreviewBlockGeometryPreferenceKey.self) { values in
                guard values != geometries else {
                    return
                }
                geometries = values
                Task { @MainActor in
                    reportPreviewPosition()
                }
            }
            .onChange(of: editorScrollPosition) { _, position in
                scrollToEditorPosition(position, proxy: proxy)
            }
            .onAppear {
                installPDFExporter()
                scrollToEditorPosition(editorScrollPosition, proxy: proxy)
            }
            .onChange(of: document.revision) { _, _ in
                installPDFExporter()
            }
            .onChange(of: theme.id) { _, _ in
                installPDFExporter()
            }
            .onDisappear {
                previewController.nativeExportPDF = nil
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        onZoomChanged(
                            PreviewZoom.scaled(
                                gestureStartZoom,
                                by: value.magnification
                            )
                        )
                    }
                    .onEnded { _ in
                        gestureStartZoom = PreviewZoom.clamped(zoom)
                    }
            )
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let parseError {
            Text("Preview update failed: \(parseError)")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.9), in: Capsule())
                .padding(.top, 8)
        } else if isParsing && document.revision == 0 {
            ProgressView()
                .controlSize(.small)
                .padding(8)
        }
    }

    private func scrollToEditorPosition(
        _ position: ScrollSyncPosition,
        proxy: ScrollViewProxy
    ) {
        guard position.generation != 0,
              position.generation != appliedEditorGeneration,
              let block = nearestBlock(to: position.sourceLine) else {
            return
        }
        appliedEditorGeneration = position.generation
        suppressPreviewReporting = true
        withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(block.id, anchor: .top)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            suppressPreviewReporting = false
        }
    }

    private func nearestBlock(to sourceLine: Int) -> PreviewBlock? {
        document.blocks.first(where: { $0.sourceRange.contains(line: sourceLine) })
            ?? document.blocks.min {
                abs($0.sourceRange.startLine - sourceLine)
                    < abs($1.sourceRange.startLine - sourceLine)
            }
    }

    private func reportPreviewPosition() {
        guard !suppressPreviewReporting,
              let geometry = geometries
                  .filter({ $0.maxY > 0 })
                  .min(by: { abs($0.minY) < abs($1.minY) }) else {
            return
        }

        let height = max(geometry.maxY - geometry.minY, 1)
        let fraction = min(max(-geometry.minY / height, 0), 1)
        let lineSpan = max(
            geometry.sourceRange.endLine - geometry.sourceRange.startLine,
            0
        )
        let sourceLine = Double(geometry.sourceRange.startLine)
            + Double(lineSpan) * fraction
        let progress = min(
            max((sourceLine - 1) / Double(max(document.lineCount - 1, 1)), 0),
            1
        )
        onPreviewScroll(sourceLine, progress, false)
    }

    private func installPDFExporter() {
        let snapshotDocument = document
        let snapshotConfiguration = configuration
        let snapshotTheme = theme
        let snapshotBaseName = documentBaseName
        previewController.nativeExportPDF = {
            NativePDFExportService.export(
                document: snapshotDocument,
                configuration: snapshotConfiguration,
                theme: snapshotTheme,
                documentURL: fileURL,
                workspaceRootURL: workspaceRootURL,
                documentBaseName: snapshotBaseName
            )
        }
    }
}

struct PreviewBlockGeometry: Equatable {
    let blockID: PreviewBlockID
    let sourceRange: PreviewSourceRange
    let minY: CGFloat
    let maxY: CGFloat
}

struct PreviewBlockGeometryPreferenceKey: PreferenceKey {
    static var defaultValue: [PreviewBlockGeometry] = []

    static func reduce(
        value: inout [PreviewBlockGeometry],
        nextValue: () -> [PreviewBlockGeometry]
    ) {
        value.append(contentsOf: nextValue())
    }
}
