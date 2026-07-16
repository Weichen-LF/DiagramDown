//
//  ScrollSyncState.swift
//  DiagramDown
//

import Foundation

struct ScrollSyncPosition: Equatable {
    let sourceLine: Int
    let progress: Double
    let generation: UInt64

    nonisolated static let initial = ScrollSyncPosition(
        sourceLine: 1,
        progress: 0,
        generation: 0
    )
}

struct ScrollSyncTarget: Equatable {
    let sourceLine: Double
    let progress: Double
    let usesProgressFallback: Bool
    let animated: Bool
    let generation: UInt64

    nonisolated static let initial = ScrollSyncTarget(
        sourceLine: 1,
        progress: 0,
        usesProgressFallback: false,
        animated: false,
        generation: 0
    )
}
