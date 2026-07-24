//
//  WorkspaceLaunchRestoration.swift
//  DiagramDown
//

import Foundation

protocol WorkspaceLaunchStorage {
    func data(forKey key: String) -> Data?
    func set(_ data: Data, forKey key: String)
}

private struct UserDefaultsWorkspaceLaunchStorage: WorkspaceLaunchStorage {
    let defaults: UserDefaults

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class WorkspaceLaunchRestoration {
    static let shared = WorkspaceLaunchRestoration()

    private let storage: any WorkspaceLaunchStorage
    private let storageKey: String
    private var didAttemptRestoration = false

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "Workspace.lastReference"
    ) {
        storage = UserDefaultsWorkspaceLaunchStorage(defaults: defaults)
        self.storageKey = storageKey
    }

    init(
        storage: any WorkspaceLaunchStorage,
        storageKey: String = "Workspace.lastReference"
    ) {
        self.storage = storage
        self.storageKey = storageKey
    }

    func remember(_ reference: WorkspaceReference) {
        guard let encoded = try? JSONEncoder().encode(reference) else {
            return
        }
        storage.set(encoded, forKey: storageKey)
    }

    func takeReferenceForLaunch() -> WorkspaceReference? {
        guard !didAttemptRestoration else {
            return nil
        }
        didAttemptRestoration = true
        guard let encoded = storage.data(forKey: storageKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkspaceReference.self, from: encoded)
    }
}
