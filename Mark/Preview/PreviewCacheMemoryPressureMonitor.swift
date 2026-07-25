//
//  PreviewCacheMemoryPressureMonitor.swift
//  DiagramDown
//

import Foundation

nonisolated struct PreviewCacheStatistics: Equatable, Sendable {
    let entryCount: Int
    let estimatedBytes: Int
}

@MainActor
final class PreviewCacheMemoryPressureMonitor {
    static let shared = PreviewCacheMemoryPressureMonitor()

    private var source: DispatchSourceMemoryPressure?

    func start() {
        guard source == nil else {
            return
        }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue(
                label: "me.walt.diagramdown.preview-memory-pressure",
                qos: .utility
            )
        )
        source.setEventHandler {
            Task {
                await TreeSitterCodeHighlighter.shared.purgeCaches()
                await DiagramRenderCoordinator.shared.purgeCaches()
            }
        }
        source.resume()
        self.source = source
    }
}
