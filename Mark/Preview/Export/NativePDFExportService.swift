//
//  NativePDFExportService.swift
//  DiagramDown
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreviewExportSnapshot {
    let document: PreviewDocument
    let resolvedCodeBlocks: [PreviewBlockID: AttributedString]
    let resolvedDiagrams: [PreviewBlockID: DiagramDocument]
    let diagramCodeFallbacks: [PreviewBlockID: AttributedString]
    let diagramErrors: [PreviewBlockID: String]
    let resolvedImages: [PreviewBlockID: NSImage]
    let theme: PreviewTheme
    let metrics: PreviewMetrics
}

@MainActor
enum NativePDFExportService {
    private static var isExporting = false

    static func export(
        document: PreviewDocument,
        configuration: PreviewConfiguration,
        theme: PreviewTheme,
        documentURL: URL?,
        workspaceRootURL: URL,
        documentBaseName: String
    ) {
        guard !isExporting else {
            return
        }
        guard document.revision != 0 else {
            showAlert(
                title: "Preview Not Ready",
                message: "Wait for the Markdown preview to finish updating, then try again."
            )
            return
        }

        isExporting = true
        Task {
            do {
                let snapshot = try await makeSnapshot(
                    document: document,
                    configuration: configuration,
                    theme: theme,
                    documentURL: documentURL,
                    workspaceRootURL: workspaceRootURL
                )
                guard let url = await destinationURL(baseName: documentBaseName) else {
                    isExporting = false
                    return
                }
                try print(snapshot: snapshot, to: url)
                isExporting = false
            } catch {
                isExporting = false
                showAlert(
                    title: "Export Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func makeSnapshot(
        document: PreviewDocument,
        configuration: PreviewConfiguration,
        theme: PreviewTheme,
        documentURL: URL?,
        workspaceRootURL: URL
    ) async throws -> PreviewExportSnapshot {
        var codeBlocks: [PreviewBlockID: AttributedString] = [:]
        var diagrams: [PreviewBlockID: DiagramDocument] = [:]
        var diagramCodeFallbacks: [PreviewBlockID: AttributedString] = [:]
        var diagramErrors: [PreviewBlockID: String] = [:]
        var images: [PreviewBlockID: NSImage] = [:]
        let dark = theme.id.hasSuffix("-dark")

        for block in flattened(document.blocks) {
            try Task.checkCancellation()
            switch block.content {
            case .code(let language, _, let source):
                codeBlocks[block.id] = await TreeSitterCodeHighlighter.shared.highlight(
                    source: source,
                    language: language,
                    theme: theme.codeTheme
                )
            case .mermaid(let source), .d2(let source):
                let kind: DiagramKind = switch block.content {
                case .mermaid: .mermaid
                default: .d2
                }
                do {
                    let result = try await DiagramRenderCoordinator.shared.render(
                        DiagramRenderRequest(
                            blockID: block.id,
                            revision: document.revision,
                            kind: kind,
                            source: source,
                            configuration: DiagramConfiguration(
                                mermaidRenderer: configuration.mermaidRenderer,
                                mermaidTheme: dark
                                    ? configuration.mermaidDarkTheme
                                    : configuration.mermaidLightTheme,
                                appearance: dark ? "dark" : "light",
                                d2: configuration.d2
                            )
                        )
                    )
                    diagrams[block.id] = result.document
                } catch is DiagramToolResolutionError {
                    diagramCodeFallbacks[block.id] =
                        await TreeSitterCodeHighlighter.shared.highlight(
                            source: source,
                            language: nil,
                            theme: theme.codeTheme
                        )
                } catch {
                    diagramErrors[block.id] = error.localizedDescription
                }
            case .image(let image):
                let data = try? await Task.detached {
                    try PreviewImageResolver.data(
                        for: image,
                        documentURL: documentURL,
                        workspaceRootURL: workspaceRootURL
                    )
                }.value
                if let data, let resolved = NSImage(data: data) {
                    images[block.id] = resolved
                }
            default:
                break
            }
        }

        return PreviewExportSnapshot(
            document: document,
            resolvedCodeBlocks: codeBlocks,
            resolvedDiagrams: diagrams,
            diagramCodeFallbacks: diagramCodeFallbacks,
            diagramErrors: diagramErrors,
            resolvedImages: images,
            theme: theme,
            metrics: PreviewMetrics(zoom: 1)
        )
    }

    private static func flattened(_ blocks: [PreviewBlock]) -> [PreviewBlock] {
        blocks.flatMap { block in
            switch block.content {
            case .blockQuote(let children):
                return [block] + flattened(children)
            case .unorderedList(let items), .orderedList(_, let items):
                return [block] + items.flatMap { flattened($0.blocks) }
            default:
                return [block]
            }
        }
    }

    private static func destinationURL(baseName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let sanitized = baseName.map { "/:".contains($0) ? "-" : $0 }
        let trimmed = String(sanitized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(trimmed.isEmpty ? "Untitled" : trimmed).pdf"

        return await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(panel.runModal())
            }
        }
    }

    private static func print(
        snapshot: PreviewExportSnapshot,
        to url: URL
    ) throws {
        let printable = NativePrintablePreviewView(snapshot: snapshot)
        let hostingView = NSHostingView(rootView: printable)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.frame = NSRect(x: 0, y: 0, width: 523, height: 1)
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = max(hostingView.fittingSize.height, 1)
        hostingView.frame = NSRect(x: 0, y: 0, width: 523, height: fittingHeight)
        hostingView.layoutSubtreeIfNeeded()

        let printInfo = NSPrintInfo()
        printInfo.paperSize = NSSize(width: 595.2, height: 841.8)
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = NSPrintOperation(view: hostingView, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = true
        guard operation.run() else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private struct NativePrintablePreviewView: View {
    let snapshot: PreviewExportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: snapshot.metrics.blockSpacing) {
            ForEach(snapshot.document.blocks) { block in
                PrintablePreviewBlockView(block: block, snapshot: snapshot)
            }
        }
        .padding(.vertical, 1)
        .frame(width: 523, alignment: .topLeading)
        .background(snapshot.theme.background)
        .foregroundStyle(snapshot.theme.primaryText)
    }
}

private struct PrintablePreviewBlockView: View {
    let block: PreviewBlock
    let snapshot: PreviewExportSnapshot

    private var theme: PreviewTheme { snapshot.theme }
    private var metrics: PreviewMetrics { snapshot.metrics }

    @ViewBuilder
    var body: some View {
        switch block.content {
        case .heading(let level, let inline):
            VStack(alignment: .leading, spacing: 4) {
                inlineText(inline, baseFont: metrics.headingFont(level: level))
                if level <= 2 {
                    Divider().overlay(theme.border)
                }
            }
        case .paragraph(let inline):
            inlineText(inline)
                .lineSpacing(3)
        case .blockQuote(let blocks):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(theme.blockQuoteBorder).frame(width: 3)
                printableBlocks(blocks)
            }
        case .unorderedList(let items):
            printableList(items: items, start: nil)
        case .orderedList(let start, let items):
            printableList(items: items, start: start)
        case .table(let table):
            printableTable(table)
        case .code(_, _, let source):
            Text(snapshot.resolvedCodeBlocks[block.id] ?? AttributedString(source))
                .font(.system(size: metrics.codeFontSize, design: .monospaced))
                .padding(metrics.codeInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(theme.codeTheme.background))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .mermaid, .d2:
            if let diagram = snapshot.resolvedDiagrams[block.id] {
                NativeDiagramView(
                    document: diagram,
                    background: theme.background
                )
                    .frame(maxWidth: .infinity, maxHeight: 620)
            } else if let source = snapshot.diagramCodeFallbacks[block.id] {
                Text(source)
                    .font(.system(size: metrics.codeFontSize, design: .monospaced))
                    .padding(metrics.codeInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(theme.codeTheme.background))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if let message = snapshot.diagramErrors[block.id] {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.system(size: metrics.bodyFontSize))
                    .foregroundStyle(.red)
                    .padding(metrics.codeInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case .thematicBreak:
            Divider().overlay(theme.border)
        case .image(let image):
            if let resolved = snapshot.resolvedImages[block.id] {
                Image(nsImage: resolved)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(image.alt.isEmpty ? "Image" : image.alt)
            } else {
                Text(image.alt.isEmpty ? "[Image]" : "[Image: \(image.alt)]")
                    .foregroundStyle(theme.secondaryText)
            }
        case .rawText(let source):
            Text(source)
                .font(.system(size: metrics.codeFontSize, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func inlineText(
        _ content: PreviewInlineContent,
        baseFont: Font? = nil
    ) -> Text {
        Text(
            InlineAttributedStringBuilder().build(
                content,
                theme: theme,
                metrics: metrics,
                baseFont: baseFont
            )
        )
    }

    private func printableBlocks(_ blocks: [PreviewBlock]) -> some View {
        VStack(alignment: .leading, spacing: metrics.blockSpacing * 0.7) {
            ForEach(blocks) { child in
                AnyView(PrintablePreviewBlockView(block: child, snapshot: snapshot))
            }
        }
    }

    private func printableList(
        items: [PreviewListItem],
        start: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(listMarker(item: item, index: index, start: start))
                        .frame(width: 24, alignment: .trailing)
                    printableBlocks(item.blocks)
                }
            }
        }
    }

    private func listMarker(
        item: PreviewListItem,
        index: Int,
        start: Int?
    ) -> String {
        if let checkbox = item.checkbox {
            return checkbox ? "☑" : "☐"
        }
        if let start {
            return "\(start + index)."
        }
        return "•"
    }

    private func printableTable(_ table: PreviewTable) -> some View {
        let rows = [table.headers] + table.rows
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inlineText(
                            cell,
                            baseFont: .system(
                                size: metrics.bodyFontSize,
                                weight: rowIndex == 0 ? .semibold : .regular
                            )
                        )
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                rowIndex == 0
                                    ? theme.subtleBackground
                                    : theme.background
                            )
                            .overlay { Rectangle().stroke(theme.border, lineWidth: 1) }
                    }
                }
            }
        }
    }
}
