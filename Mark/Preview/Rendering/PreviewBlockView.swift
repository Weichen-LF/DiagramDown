//
//  PreviewBlockView.swift
//  DiagramDown
//

import AppKit
import SwiftUI

struct PreviewBlockView: View {
    let block: PreviewBlock
    let revision: UInt64
    let configuration: PreviewConfiguration
    let theme: PreviewTheme
    let metrics: PreviewMetrics
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let onSourceLineSelected: (Int) -> Void

    @ViewBuilder
    var body: some View {
        Group {
            switch block.content {
            case .heading(let level, let inline):
                heading(level: level, inline: inline)

            case .paragraph(let inline):
                inlineText(inline)
                    .lineSpacing(3 * metrics.zoom)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .blockQuote(let blocks):
                HStack(alignment: .top, spacing: 12 * metrics.zoom) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.blockQuoteBorder)
                        .frame(width: max(3, 3 * metrics.zoom))
                    NestedPreviewBlocksView(
                        blocks: blocks,
                        revision: revision,
                        configuration: configuration,
                        theme: theme,
                        metrics: metrics,
                        fileURL: fileURL,
                        workspaceRootURL: workspaceRootURL,
                        documentBaseName: documentBaseName,
                        onSourceLineSelected: onSourceLineSelected
                    )
                    .foregroundStyle(theme.secondaryText)
                }

            case .unorderedList(let items):
                PreviewListView(
                    items: items,
                    start: nil,
                    revision: revision,
                    configuration: configuration,
                    theme: theme,
                    metrics: metrics,
                    fileURL: fileURL,
                    workspaceRootURL: workspaceRootURL,
                    documentBaseName: documentBaseName,
                    onSourceLineSelected: onSourceLineSelected
                )

            case .orderedList(let start, let items):
                PreviewListView(
                    items: items,
                    start: start,
                    revision: revision,
                    configuration: configuration,
                    theme: theme,
                    metrics: metrics,
                    fileURL: fileURL,
                    workspaceRootURL: workspaceRootURL,
                    documentBaseName: documentBaseName,
                    onSourceLineSelected: onSourceLineSelected
                )

            case .table(let table):
                PreviewTableView(
                    table: table,
                    theme: theme,
                    metrics: metrics
                )

            case .code(let language, let rawLanguage, let source):
                CodeBlockView(
                    source: source,
                    language: language,
                    rawLanguage: rawLanguage,
                    theme: theme,
                    metrics: metrics
                )

            case .mermaid(let source):
                DiagramBlockView(
                    blockID: block.id,
                    revision: revision,
                    sourceRange: block.sourceRange,
                    kind: .mermaid,
                    source: source,
                    configuration: configuration,
                    theme: theme,
                    metrics: metrics,
                    documentBaseName: documentBaseName,
                    onSourceLineSelected: onSourceLineSelected
                )

            case .d2(let source):
                DiagramBlockView(
                    blockID: block.id,
                    revision: revision,
                    sourceRange: block.sourceRange,
                    kind: .d2,
                    source: source,
                    configuration: configuration,
                    theme: theme,
                    metrics: metrics,
                    documentBaseName: documentBaseName,
                    onSourceLineSelected: onSourceLineSelected
                )

            case .thematicBreak:
                Divider()
                    .overlay(theme.border)
                    .padding(.vertical, 4 * metrics.zoom)

            case .image(let image):
                PreviewImageView(
                    image: image,
                    documentURL: fileURL,
                    workspaceRootURL: workspaceRootURL,
                    theme: theme,
                    metrics: metrics
                )

            case .rawText(let source):
                Text(source)
                    .font(.system(size: metrics.codeFontSize, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .padding(metrics.codeInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.subtleBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 7 * metrics.zoom))
                    .accessibilityLabel("Raw HTML shown as text")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSourceLineSelected(block.sourceRange.startLine)
        }
    }

    @ViewBuilder
    private func heading(
        level: Int,
        inline: PreviewInlineContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6 * metrics.zoom) {
            inlineText(inline, baseFont: metrics.headingFont(level: level))
                .frame(maxWidth: .infinity, alignment: .leading)
            if level <= 2 {
                Divider().overlay(theme.border)
            }
        }
        .padding(.top, level == 1 ? 8 * metrics.zoom : 3 * metrics.zoom)
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
}

private struct NestedPreviewBlocksView: View {
    let blocks: [PreviewBlock]
    let revision: UInt64
    let configuration: PreviewConfiguration
    let theme: PreviewTheme
    let metrics: PreviewMetrics
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let onSourceLineSelected: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.blockSpacing * 0.7) {
            ForEach(blocks) { block in
                AnyView(
                    PreviewBlockView(
                        block: block,
                        revision: revision,
                        configuration: configuration,
                        theme: theme,
                        metrics: metrics,
                        fileURL: fileURL,
                        workspaceRootURL: workspaceRootURL,
                        documentBaseName: documentBaseName,
                        onSourceLineSelected: onSourceLineSelected
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreviewListView: View {
    let items: [PreviewListItem]
    let start: Int?
    let revision: UInt64
    let configuration: PreviewConfiguration
    let theme: PreviewTheme
    let metrics: PreviewMetrics
    let fileURL: URL?
    let workspaceRootURL: URL
    let documentBaseName: String
    let onSourceLineSelected: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7 * metrics.zoom) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 9 * metrics.zoom) {
                    marker(for: item, index: index)
                        .frame(minWidth: 20 * metrics.zoom, alignment: .trailing)
                    NestedPreviewBlocksView(
                        blocks: item.blocks,
                        revision: revision,
                        configuration: configuration,
                        theme: theme,
                        metrics: metrics,
                        fileURL: fileURL,
                        workspaceRootURL: workspaceRootURL,
                        documentBaseName: documentBaseName,
                        onSourceLineSelected: onSourceLineSelected
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSourceLineSelected(item.sourceRange.startLine)
                }
            }
        }
        .padding(.leading, 4 * metrics.zoom)
    }

    @ViewBuilder
    private func marker(for item: PreviewListItem, index: Int) -> some View {
        if let checkbox = item.checkbox {
            Image(systemName: checkbox ? "checkmark.square.fill" : "square")
                .foregroundStyle(checkbox ? theme.accent : theme.secondaryText)
                .font(.system(size: metrics.bodyFontSize))
                .accessibilityLabel(checkbox ? "Completed task" : "Incomplete task")
        } else if let start {
            Text("\(start + index).")
                .font(.system(size: metrics.bodyFontSize))
                .foregroundStyle(theme.secondaryText)
        } else {
            Text("•")
                .font(.system(size: metrics.bodyFontSize))
                .foregroundStyle(theme.secondaryText)
        }
    }
}

private struct PreviewTableView: View {
    let table: PreviewTable
    let theme: PreviewTheme
    let metrics: PreviewMetrics

    private var allRows: [[PreviewInlineContent]] {
        [table.headers] + table.rows
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(allRows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            Text(
                                InlineAttributedStringBuilder().build(
                                    cell,
                                    theme: theme,
                                    metrics: metrics,
                                    baseFont: .system(
                                        size: metrics.bodyFontSize,
                                        weight: rowIndex == 0 ? .semibold : .regular
                                    )
                                )
                            )
                            .padding(metrics.tableCellInset)
                            .frame(
                                minWidth: 110 * metrics.zoom,
                                maxWidth: 280 * metrics.zoom,
                                alignment: alignment(for: column)
                            )
                            .background(
                                rowIndex == 0
                                    ? theme.subtleBackground
                                    : theme.background
                            )
                            .overlay {
                                Rectangle()
                                    .stroke(theme.border, lineWidth: 1)
                            }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.visible)
    }

    private func alignment(for column: Int) -> SwiftUI.Alignment {
        guard table.alignments.indices.contains(column) else {
            return .leading
        }
        return switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
