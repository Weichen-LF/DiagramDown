//
//  DiagramRenderCoordinator.swift
//  DiagramDown
//

import CoreGraphics
import Foundation

nonisolated enum DiagramKind: String, Hashable, Sendable {
    case mermaid
    case d2
}

nonisolated struct DiagramConfiguration: Hashable, Sendable {
    let mermaidRenderer: MermaidRendererEngine
    let mermaidTheme: MermaidPreviewTheme
    let appearance: String
    let d2: D2RenderConfiguration
}

nonisolated struct DiagramRenderRequest: Hashable, Sendable {
    let blockID: PreviewBlockID
    let revision: UInt64
    let kind: DiagramKind
    let source: String
    let configuration: DiagramConfiguration
}

nonisolated struct DiagramRenderResult: Sendable {
    let blockID: PreviewBlockID
    let revision: UInt64
    let document: DiagramDocument
    let cacheKey: String
}

actor DiagramRenderCoordinator {
    static let shared = DiagramRenderCoordinator()

    private let toolRegistry: DiagramToolRegistry
    private let d2RenderService: D2RenderService
    private let mermaidRenderService: MermaidRenderService
    private var cache: [String: DiagramDocument] = [:]
    private var cacheOrder: [String] = []
    private var cacheCost = 0
    private let maximumEntries = 128
    private let maximumMemoryCacheBytes = 64 * 1_024 * 1_024
    private let maximumCachedOutputBytes = 16 * 1_024 * 1_024
    private let maximumDiskCacheBytes = 256 * 1_024 * 1_024
    private let diskCacheTrimTargetBytes = 224 * 1_024 * 1_024
    private let diskCacheDirectoryURL: URL?

    init(
        toolRegistry: DiagramToolRegistry = .shared,
        d2RenderService: D2RenderService = .shared,
        mermaidRenderService: MermaidRenderService = .shared,
        diskCacheDirectoryURL: URL? = DiagramRenderCoordinator.defaultDiskCacheDirectoryURL()
    ) {
        self.toolRegistry = toolRegistry
        self.d2RenderService = d2RenderService
        self.mermaidRenderService = mermaidRenderService
        self.diskCacheDirectoryURL = diskCacheDirectoryURL
    }

    func cacheStatistics() -> PreviewCacheStatistics {
        PreviewCacheStatistics(
            entryCount: cache.count,
            estimatedBytes: cacheCost
        )
    }

    func purgeCaches() {
        cache.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
        cacheCost = 0
    }

    func purgeAllCaches() throws {
        purgeCaches()
        guard let diskCacheDirectoryURL,
              FileManager.default.fileExists(atPath: diskCacheDirectoryURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: diskCacheDirectoryURL)
    }

    func render(_ request: DiagramRenderRequest) async throws -> DiagramRenderResult {
        try Task.checkCancellation()
        let toolKind: DiagramToolKind = switch request.kind {
        case .mermaid: request.configuration.mermaidRenderer.toolKind
        case .d2: .d2
        }
        let tool = try await toolRegistry.installedTool(for: toolKind)
        let key = cacheKey(for: request, tool: tool)
        if let cached = cache[key] {
            return result(for: request, document: cached, cacheKey: key)
        }
        if let cached = try await diskCachedDocument(
            forKey: key,
            kind: request.kind,
            mermaidRenderer: request.configuration.mermaidRenderer
        ) {
            storeInMemory(cached, forKey: key)
            return result(for: request, document: cached, cacheKey: key)
        }

        let document: DiagramDocument
        switch request.kind {
        case .d2:
            let rawSVG = try await d2RenderService.render(
                source: request.source,
                configuration: request.configuration.d2,
                appearance: request.configuration.appearance,
                tool: tool
            ).svg
            document = .svg(try await SVGSanitizer.shared.sanitize(rawSVG))
        case .mermaid:
            switch request.configuration.mermaidRenderer {
            case .mmdc:
                let png = try await mermaidRenderService.renderPNG(
                    source: request.source,
                    theme: request.configuration.mermaidTheme,
                    appearance: request.configuration.appearance,
                    tool: tool
                )
                document = .raster(
                    try RasterDiagramDocument(
                        data: png,
                        displayScale: CGFloat(MermaidRenderService.pngScale)
                    )
                )
            case .mmdr:
                let rawSVG = try await mermaidRenderService.renderSVG(
                    source: request.source,
                    theme: request.configuration.mermaidTheme,
                    engine: .mmdr,
                    tool: tool
                )
                document = .svg(try await SVGSanitizer.shared.sanitize(rawSVG))
            }
        }
        try Task.checkCancellation()

        storeInMemory(document, forKey: key)
        storeOnDisk(
            document,
            forKey: key,
            kind: request.kind,
            mermaidRenderer: request.configuration.mermaidRenderer
        )

        return result(for: request, document: document, cacheKey: key)
    }

    func renderMermaidSVG(_ request: DiagramRenderRequest) async throws -> String {
        guard request.kind == .mermaid else {
            throw MermaidRenderError.invalidSVG
        }
        let engine = request.configuration.mermaidRenderer
        let tool = try await toolRegistry.installedTool(for: engine.toolKind)
        return try await mermaidRenderService.renderSVG(
            source: request.source,
            theme: request.configuration.mermaidTheme,
            engine: engine,
            tool: tool
        )
    }

    private func result(
        for request: DiagramRenderRequest,
        document: DiagramDocument,
        cacheKey: String
    ) -> DiagramRenderResult {
        DiagramRenderResult(
            blockID: request.blockID,
            revision: request.revision,
            document: document,
            cacheKey: cacheKey
        )
    }

    private func storeInMemory(_ document: DiagramDocument, forKey key: String) {
        if let previous = cache[key] {
            cacheCost -= previous.byteCount
        }
        cache[key] = document
        cacheCost += document.byteCount
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.append(key)
        while cacheOrder.count > maximumEntries
            || cacheCost > maximumMemoryCacheBytes {
            let removedKey = cacheOrder.removeFirst()
            if let removed = cache.removeValue(forKey: removedKey) {
                cacheCost -= removed.byteCount
            }
        }
    }

    private func diskCachedDocument(
        forKey key: String,
        kind: DiagramKind,
        mermaidRenderer: MermaidRendererEngine
    ) async throws -> DiagramDocument? {
        guard let url = diskCacheFileURL(
            forKey: key,
            kind: kind,
            mermaidRenderer: mermaidRenderer
        ) else {
            return nil
        }
        do {
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize,
                  fileSize <= maximumCachedOutputBytes else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumCachedOutputBytes else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
            switch kind {
            case .mermaid:
                switch mermaidRenderer {
                case .mmdc:
                    guard let raster = try? RasterDiagramDocument(
                        data: data,
                        displayScale: CGFloat(MermaidRenderService.pngScale)
                    ) else {
                        try? FileManager.default.removeItem(at: url)
                        return nil
                    }
                    return .raster(raster)
                case .mmdr:
                    guard let svg = String(data: data, encoding: .utf8),
                          let sanitized = try? await SVGSanitizer.shared.sanitize(svg) else {
                        try? FileManager.default.removeItem(at: url)
                        return nil
                    }
                    return .svg(sanitized)
                }
            case .d2:
                guard let svg = String(data: data, encoding: .utf8),
                      let sanitized = try? await SVGSanitizer.shared.sanitize(svg) else {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return .svg(sanitized)
            }
        } catch {
            return nil
        }
    }

    private func storeOnDisk(
        _ document: DiagramDocument,
        forKey key: String,
        kind: DiagramKind,
        mermaidRenderer: MermaidRendererEngine
    ) {
        let data: Data = switch document {
        case .svg(let svg):
            Data(svg.sanitizedXML.utf8)
        case .raster(let raster):
            raster.data
        }
        guard data.count <= maximumCachedOutputBytes,
              let url = diskCacheFileURL(
                forKey: key,
                kind: kind,
                mermaidRenderer: mermaidRenderer
              ) else {
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            trimDiskCacheIfNeeded()
        } catch {
            return
        }
    }

    private func trimDiskCacheIfNeeded() {
        guard let root = diskCacheDirectoryURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey,
                ],
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        var entries: [(url: URL, size: Int, date: Date)] = []
        var totalSize = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
            ]),
            values.isRegularFile == true,
            let size = values.fileSize else {
                continue
            }
            totalSize += size
            entries.append((
                url: url,
                size: size,
                date: values.contentModificationDate ?? .distantPast
            ))
        }
        guard totalSize > maximumDiskCacheBytes else {
            return
        }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            try? FileManager.default.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= diskCacheTrimTargetBytes {
                break
            }
        }
    }

    private func diskCacheFileURL(
        forKey key: String,
        kind: DiagramKind,
        mermaidRenderer: MermaidRendererEngine
    ) -> URL? {
        guard key.count >= 4, let root = diskCacheDirectoryURL else {
            return nil
        }
        let fileExtension: String
        switch kind {
        case .d2:
            fileExtension = "svg"
        case .mermaid:
            fileExtension = mermaidRenderer == .mmdr ? "svg" : "png"
        }
        return root
            .appendingPathComponent(String(key.prefix(2)), isDirectory: true)
            .appendingPathComponent(
                String(key.dropFirst(2).prefix(2)),
                isDirectory: true
            )
            .appendingPathComponent(
                "\(key).\(fileExtension)",
                isDirectory: false
            )
    }

    nonisolated private static func defaultDiskCacheDirectoryURL() -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return caches
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "me.walt.diagramdown",
                isDirectory: true
            )
            .appendingPathComponent("preview-diagrams", isDirectory: true)
    }

    private func cacheKey(
        for request: DiagramRenderRequest,
        tool: InstalledDiagramTool
    ) -> String {
        let rendererMaterial: [String]
        let formatToken: String
        switch request.kind {
        case .d2:
            rendererMaterial = [
                D2RenderService.rendererVersion,
                tool.cacheDescriptor,
                request.configuration.d2.cacheDescriptor,
                request.configuration.appearance,
            ]
            formatToken = "svg-sanitizer-v3-remove-canvas"
        case .mermaid:
            switch request.configuration.mermaidRenderer {
            case .mmdc:
                rendererMaterial = [
                    MermaidRenderService.mmdcRendererVersion,
                    tool.cacheDescriptor,
                    request.configuration.mermaidTheme.rawValue,
                    request.configuration.appearance,
                    "\(MermaidRenderService.pngScale)",
                ]
                formatToken = "png-preview-v1"
            case .mmdr:
                rendererMaterial = [
                    MermaidRenderService.mmdrRendererVersion,
                    tool.cacheDescriptor,
                    request.configuration.appearance,
                ]
                formatToken = "svg-sanitizer-v3-remove-canvas"
            }
        }

        return MarkdownParserService.digest(
            ([
                request.kind.rawValue,
                request.configuration.mermaidRenderer.rawValue,
                MarkdownParserService.digest(request.source),
            ] + rendererMaterial + [
                formatToken,
            ]).joined(separator: "\u{0}")
        )
    }
}
