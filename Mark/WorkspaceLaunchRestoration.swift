//
//  WorkspaceLaunchRestoration.swift
//  DiagramDown
//

import Foundation

@MainActor
final class WorkspaceLaunchRestoration {
    static let shared = WorkspaceLaunchRestoration()

    private let defaults: UserDefaults
    private let storageKey: String
    private var didAttemptRestoration = false

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
        guard !didAttemptRestoration else {
            return nil
        }
        didAttemptRestoration = true
        guard let encoded = defaults.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceReference.self, from: encoded)
    }
}
