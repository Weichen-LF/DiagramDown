//
//  PreviewDocumentReconciler.swift
//  DiagramDown
//

import Foundation

nonisolated struct PreviewDocumentReconciler {
    func reconcile(
        newBlocks: [PreviewBlock],
        previousBlocks: [PreviewBlock]
    ) -> [PreviewBlock] {
        guard !previousBlocks.isEmpty else {
            return newBlocks
        }

        var claimed = Set<PreviewBlockID>()
        return newBlocks.map { block in
            if let exact = nearestMatch(
                for: block,
                in: previousBlocks,
                claimed: claimed,
                where: { $0.fingerprint == block.fingerprint }
            ) {
                claimed.insert(exact.id)
                return block.replacingID(exact.id)
            }

            if let overlapping = nearestMatch(
                for: block,
                in: previousBlocks,
                claimed: claimed,
                where: {
                    $0.content.kind == block.content.kind
                        && $0.sourceRange.overlaps(block.sourceRange)
                }
            ) {
                claimed.insert(overlapping.id)
                return block.replacingID(overlapping.id)
            }

            return block
        }
    }

    private func nearestMatch(
        for block: PreviewBlock,
        in candidates: [PreviewBlock],
        claimed: Set<PreviewBlockID>,
        where predicate: (PreviewBlock) -> Bool
    ) -> PreviewBlock? {
        candidates
            .filter { !claimed.contains($0.id) && predicate($0) }
            .min {
                abs($0.sourceRange.startLine - block.sourceRange.startLine)
                    < abs($1.sourceRange.startLine - block.sourceRange.startLine)
            }
    }
}
