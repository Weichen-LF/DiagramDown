//
//  WorkspaceLaunchRestoration.swift
//  DiagramDown
//

import Foundation

nonisolated struct WorkspaceLaunchState {
    private(set) var didAttemptRestoration = false

    mutating func takeReference(from encoded: Data?) -> WorkspaceReference? {
        guard !didAttemptRestoration else {
            return nil
        }
        didAttemptRestoration = true
        guard let encoded else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceReference.self, from: encoded)
    }
}

@MainActor
final class WorkspaceLaunchRestoration {
    static let shared = WorkspaceLaunchRestoration()

    private let defaults: UserDefaults
    private let storageKey: String
    private var state = WorkspaceLaunchState()

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "Workspace.lastReference"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func remember(_ reference: WorkspaceReference) {
        guard let encoded = try? JSONEncoder().encode(reference) else {
            return
        }
        defaults.set(encoded, forKey: storageKey)
    }

    func takeReferenceForLaunch() -> WorkspaceReference? {
        state.takeReference(from: defaults.data(forKey: storageKey))
    }
}
