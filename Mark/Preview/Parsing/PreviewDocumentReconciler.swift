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

        var previousByFingerprint: [String: [Int]] = [:]
        for (index, block) in previousBlocks.enumerated() {
            previousByFingerprint[block.fingerprint, default: []].append(index)
        }

        var fingerprintCursors: [String: Int] = [:]
        var claimedPrevious = Set<Int>()
        var matches: [Int: PreviewBlockID] = [:]

        // Exact content matches are paired in document order. This makes
        // duplicate blocks deterministic without repeatedly scanning all old
        // blocks.
        for (newIndex, block) in newBlocks.enumerated() {
            let cursor = fingerprintCursors[block.fingerprint, default: 0]
            guard let candidates = previousByFingerprint[block.fingerprint],
                  cursor < candidates.count else {
                continue
            }
            let previousIndex = candidates[cursor]
            fingerprintCursors[block.fingerprint] = cursor + 1
            claimedPrevious.insert(previousIndex)
            matches[newIndex] = previousBlocks[previousIndex].id
        }

        var previousByKind: [String: [Int]] = [:]
        for (index, block) in previousBlocks.enumerated()
        where !claimedPrevious.contains(index) {
            previousByKind[block.content.kind, default: []].append(index)
        }

        var newByKind: [String: [Int]] = [:]
        for (index, block) in newBlocks.enumerated()
        where matches[index] == nil {
            newByKind[block.content.kind, default: []].append(index)
        }

        // Top-level Markdown blocks are source ordered and do not nest. A
        // range sweep therefore considers each unmatched block at most once.
        for (kind, newIndices) in newByKind {
            guard let previousIndices = previousByKind[kind] else {
                continue
            }
            let sortedNew = newIndices.sorted {
                newBlocks[$0].sourceRange.startLine
                    < newBlocks[$1].sourceRange.startLine
            }
            let sortedPrevious = previousIndices.sorted {
                previousBlocks[$0].sourceRange.startLine
                    < previousBlocks[$1].sourceRange.startLine
            }
            var newCursor = 0
            var previousCursor = 0

            while newCursor < sortedNew.count,
                  previousCursor < sortedPrevious.count {
                let newIndex = sortedNew[newCursor]
                let previousIndex = sortedPrevious[previousCursor]
                let newRange = newBlocks[newIndex].sourceRange
                let previousRange = previousBlocks[previousIndex].sourceRange

                if newRange.overlaps(previousRange) {
                    matches[newIndex] = previousBlocks[previousIndex].id
                    newCursor += 1
                    previousCursor += 1
                } else if previousRange.endLine < newRange.startLine {
                    previousCursor += 1
                } else {
                    newCursor += 1
                }
            }
        }

        return newBlocks.enumerated().map { index, block in
            guard let matchedID = matches[index] else {
                return block
            }
            return block.replacingID(matchedID)
        }
    }
}
