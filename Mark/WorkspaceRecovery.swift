//
//  WorkspaceRecovery.swift
//  DiagramDown
//

import Foundation

nonisolated struct WorkspaceRecoverySnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let workspaceID: UUID
    let updatedAt: Date
    let openFiles: [WorkspaceBufferRecoverySnapshot]
    let activeFileID: UUID?
    let sidebarVisible: Bool
    let sidebarWidth: Double?
    let windowFrame: WorkspaceWindowFrame?
    let expandedDirectoryIDs: Set<String>

    init(
        schemaVersion: Int = currentSchemaVersion,
        workspaceID: UUID,
        updatedAt: Date = Date(),
        openFiles: [WorkspaceBufferRecoverySnapshot],
        activeFileID: UUID?,
        sidebarVisible: Bool,
        sidebarWidth: Double? = nil,
        windowFrame: WorkspaceWindowFrame? = nil,
        expandedDirectoryIDs: Set<String>
    ) {
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.updatedAt = updatedAt
        self.openFiles = openFiles
        self.activeFileID = activeFileID
        self.sidebarVisible = sidebarVisible
        self.sidebarWidth = sidebarWidth
        self.windowFrame = windowFrame
        self.expandedDirectoryIDs = expandedDirectoryIDs
    }
}

nonisolated struct WorkspaceWindowFrame: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct WorkspaceBufferRecoverySnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let relativePath: String
    let text: String
    let savedTextFingerprint: String
    let storedViewMode: String
    let editorSourceLine: Int
    let editorScrollProgress: Double
}

actor WorkspaceRecoveryStore {
    static let shared = WorkspaceRecoveryStore()

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("DiagramDown", isDirectory: true)
                .appendingPathComponent("Workspace Recovery", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func load(workspaceID: UUID) throws -> WorkspaceRecoverySnapshot? {
        let url = snapshotURL(for: workspaceID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(
                  WorkspaceRecoverySnapshot.self,
                  from: data
              ) else {
            return nil
        }
        guard snapshot.schemaVersion == WorkspaceRecoverySnapshot.currentSchemaVersion,
              snapshot.workspaceID == workspaceID else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: WorkspaceRecoverySnapshot) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshot).write(
            to: snapshotURL(for: snapshot.workspaceID),
            options: .atomic
        )
    }

    func remove(workspaceID: UUID) throws {
        let url = snapshotURL(for: workspaceID)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func snapshotURL(for workspaceID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(workspaceID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }
}
