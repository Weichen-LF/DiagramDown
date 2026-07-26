//
//  WorkspaceLaunchRestoration.swift
//  DiagramDown
//

import Combine
import Foundation

protocol WorkspaceLaunchStorage: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: WorkspaceLaunchStorage {}

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
final class WorkspaceLaunchRestoration: ObservableObject {
    static let shared = WorkspaceLaunchRestoration()

    private let defaults: any WorkspaceLaunchStorage
    private let storageKey: String
    private let recentStorageKey: String
    private var state = WorkspaceLaunchState()
    @Published private(set) var recentWorkspaces: [RecentWorkspace] = []

    init(
        defaults: any WorkspaceLaunchStorage = UserDefaults.standard,
        storageKey: String = "Workspace.lastReference",
        recentStorageKey: String? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.recentStorageKey = recentStorageKey ?? "\(storageKey).recent"
        if let data = defaults.data(forKey: self.recentStorageKey),
           let decoded = try? JSONDecoder().decode([RecentWorkspace].self, from: data) {
            recentWorkspaces = Array(decoded.prefix(10))
        }
    }

    func remember(_ reference: WorkspaceReference) {
        guard let encoded = try? JSONEncoder().encode(reference) else {
            return
        }
        defaults.set(encoded, forKey: storageKey)
        let resolvedReferenceURL = resolvedURL(for: reference)?.standardizedFileURL
        let displayName = resolvedReferenceURL?.lastPathComponent ?? "Folder"
        recentWorkspaces.removeAll { recent in
            if recent.reference.id == reference.id {
                return true
            }
            guard let resolvedReferenceURL else {
                return false
            }
            return resolvedURL(for: recent.reference)?.standardizedFileURL
                == resolvedReferenceURL
        }
        recentWorkspaces.insert(
            RecentWorkspace(
                reference: reference,
                displayName: displayName,
                lastOpenedAt: Date()
            ),
            at: 0
        )
        recentWorkspaces = Array(recentWorkspaces.prefix(10))
        persistRecents()
    }

    func takeReferenceForLaunch() -> WorkspaceReference? {
        state.takeReference(from: defaults.data(forKey: storageKey))
    }

    func clearRecentWorkspaces() {
        recentWorkspaces = []
        defaults.removeObject(forKey: recentStorageKey)
    }

    private func resolvedURL(for reference: WorkspaceReference) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func persistRecents() {
        guard let data = try? JSONEncoder().encode(recentWorkspaces) else {
            return
        }
        defaults.set(data, forKey: recentStorageKey)
    }
}

nonisolated struct RecentWorkspace: Codable, Equatable, Identifiable, Sendable {
    let reference: WorkspaceReference
    let displayName: String
    let lastOpenedAt: Date

    var id: UUID { reference.id }
}
