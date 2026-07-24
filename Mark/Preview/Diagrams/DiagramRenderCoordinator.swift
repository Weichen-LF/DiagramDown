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
    let document: SVGDocument
    let cacheKey: String
}

actor DiagramRenderCoordinator {
    static let shared = DiagramRenderCoordinator()

    private var cache: [String: SVGDocument] = [:]
    private var cacheOrder: [String] = []
    private let maximumEntries = 128
    private let maximumSVGBytes = 8 * 1_024 * 1_024
    private let maximumDiskCacheBytes = 256 * 1_024 * 1_024
    private let diskCacheTrimTargetBytes = 224 * 1_024 * 1_024

    func render(_ request: DiagramRenderRequest) async throws -> DiagramRenderResult {
        try Task.checkCancellation()
        let key = cacheKey(for: request)
        if let cached = cache[key] {
            return result(for: request, document: cached, cacheKey: key)
        }
        if let diskSVG = diskCachedSVG(forKey: key),
           let cached = try? await SVGSanitizer.shared.sanitize(diskSVG) {
            storeInMemory(cached, forKey: key)
            return result(for: request, document: cached, cacheKey: key)
        }

        let rawSVG: String
        switch request.kind {
        case .d2:
            rawSVG = try await D2RenderService.shared.render(
                source: request.source,
                configuration: request.configuration.d2
            ).svg
        case .mermaid:
            rawSVG = try await MermaidRenderService.shared.render(
                source: request.source,
                theme: request.configuration.mermaidTheme,
                appearance: request.configuration.appearance
            )
        }
        try Task.checkCancellation()
        let sanitized = try await SVGSanitizer.shared.sanitize(rawSVG)
        try Task.checkCancellation()

        storeInMemory(sanitized, forKey: key)
        storeOnDisk(sanitized, forKey: key)

        return result(for: request, document: sanitized, cacheKey: key)
    }

    private func result(
        for request: DiagramRenderRequest,
        document: SVGDocument,
        cacheKey: String
    ) -> DiagramRenderResult {
        DiagramRenderResult(
            blockID: request.blockID,
            revision: request.revision,
            document: document,
            cacheKey: cacheKey
        )
    }

    private func storeInMemory(_ document: SVGDocument, forKey key: String) {
        cache[key] = document
        cacheOrder.removeAll(where: { $0 == key })
        cacheOrder.append(key)
        while cacheOrder.count > maximumEntries {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func diskCachedSVG(forKey key: String) -> String? {
        guard let url = diskCacheFileURL(forKey: key) else {
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
                  fileSize <= maximumSVGBytes else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= maximumSVGBytes,
                  let svg = String(data: data, encoding: .utf8) else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            try? FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: url.path
            )
            return svg
        } catch {
            return nil
        }
    }

    private func storeOnDisk(_ document: SVGDocument, forKey key: String) {
        let data = Data(document.sanitizedXML.utf8)
        guard data.count <= maximumSVGBytes,
              let url = diskCacheFileURL(forKey: key) else {
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

    private func diskCacheFileURL(forKey key: String) -> URL? {
        guard key.count >= 4, let root = diskCacheDirectoryURL else {
            return nil
        }
        return root
            .appendingPathComponent(String(key.prefix(2)), isDirectory: true)
            .appendingPathComponent(
                String(key.dropFirst(2).prefix(2)),
                isDirectory: true
            )
            .appendingPathComponent("\(key).svg", isDirectory: false)
    }

    private var diskCacheDirectoryURL: URL? {
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

    private func cacheKey(for request: DiagramRenderRequest) -> String {
        let rendererMaterial: [String]
        switch request.kind {
        case .d2:
            rendererMaterial = [
                D2RenderService.rendererVersion,
                request.configuration.d2.cacheDescriptor,
            ]
        case .mermaid:
            rendererMaterial = [
                MermaidRenderService.rendererVersion,
                request.configuration.mermaidTheme.rawValue,
                request.configuration.appearance,
            ]
        }

        MarkdownParserService.digest(
            ([
                request.kind.rawValue,
                MarkdownParserService.digest(request.source),
            ] + rendererMaterial + [
                "svg-sanitizer-v1",
            ]).joined(separator: "\u{0}")
        )
    }
}
