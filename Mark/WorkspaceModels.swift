//
//  WorkspaceModels.swift
//  DiagramDown
//

import CryptoKit
import Combine
import Foundation

struct WorkspaceReference: Codable, Hashable, Identifiable {
    let id: UUID
    let bookmarkData: Data

    init(id: UUID = UUID(), bookmarkData: Data) {
        self.id = id
        self.bookmarkData = bookmarkData
    }

    static func create(for folderURL: URL) throws -> WorkspaceReference {
        let bookmarkData = try folderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return WorkspaceReference(bookmarkData: bookmarkData)
    }
}

final class SecurityScopedAccess {
    let url: URL
    let refreshedBookmarkData: Data?
    private let didStartAccessing: Bool

    init(reference: WorkspaceReference) throws {
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: reference.bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ).standardizedFileURL
        let refreshedBookmarkData = isStale
            ? try resolvedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            : nil
        url = resolvedURL
        self.refreshedBookmarkData = refreshedBookmarkData
        didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()
    }

    deinit {
        if didStartAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

nonisolated enum WorkspacePathPolicy {
    nonisolated static func contains(_ candidateURL: URL, within rootURL: URL) -> Bool {
        let rootComponents = normalized(rootURL).pathComponents
        let candidateComponents = normalized(candidateURL).pathComponents
        guard candidateComponents.count >= rootComponents.count else {
            return false
        }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }

    nonisolated static func relativePath(
        of candidateURL: URL,
        within rootURL: URL
    ) -> String? {
        let root = normalized(rootURL)
        let candidate = normalized(candidateURL)
        guard contains(candidate, within: root) else {
            return nil
        }
        return candidate.pathComponents
            .dropFirst(root.pathComponents.count)
            .joined(separator: "/")
    }

    nonisolated private static func normalized(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

nonisolated struct FileTreeNode: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case directory
        case markdownFile
        case otherFile
    }

    let relativePath: String
    let name: String
    let kind: Kind

    nonisolated var id: String { relativePath }
    nonisolated var isDirectory: Bool { kind == .directory }
    nonisolated var canOpen: Bool { kind == .markdownFile }
}

nonisolated struct WorkspaceTreeRow: Identifiable, Hashable, Sendable {
    let node: FileTreeNode
    let depth: Int

    nonisolated var id: String { node.id }
}

actor WorkspaceFileService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func children(of directoryURL: URL, within rootURL: URL) throws -> [FileTreeNode] {
        guard WorkspacePathPolicy.contains(directoryURL, within: rootURL) else {
            throw CocoaError(.fileReadNoPermission)
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .isPackageKey,
        ]
        let childURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        return try childURLs.compactMap { childURL in
            guard childURL.lastPathComponent != ".DS_Store",
                  WorkspacePathPolicy.contains(childURL, within: rootURL),
                  let relativePath = WorkspacePathPolicy.relativePath(
                    of: childURL,
                    within: rootURL
                  ) else {
                return nil
            }

            let values = try childURL.resourceValues(forKeys: resourceKeys)
            guard values.isSymbolicLink != true else {
                return nil
            }

            let kind: FileTreeNode.Kind
            if values.isDirectory == true, values.isPackage != true {
                kind = .directory
            } else if values.isRegularFile == true || values.isPackage == true {
                let fileExtension = childURL.pathExtension.lowercased()
                kind = ["md", "markdown"].contains(fileExtension)
                    ? .markdownFile
                    : .otherFile
            } else {
                return nil
            }

            return FileTreeNode(
                relativePath: relativePath,
                name: childURL.lastPathComponent,
                kind: kind
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

enum WorkspaceBufferCloseDecision: Equatable {
    case close
    case needsConfirmation
}

@MainActor
final class OpenFileBuffer: ObservableObject, Identifiable {
    let id: UUID
    let url: URL
    let editorPreviewSession: EditorPreviewSessionState

    @Published var text: String {
        didSet {
            currentTextFingerprint = Self.fingerprint(text)
        }
    }

    @Published private(set) var savedTextFingerprint: String
    private var currentTextFingerprint: String

    init(
        id: UUID = UUID(),
        url: URL,
        text: String,
        editorPreviewSession: EditorPreviewSessionState? = nil
    ) {
        let fingerprint = Self.fingerprint(text)
        self.id = id
        self.url = url.standardizedFileURL
        self.text = text
        self.editorPreviewSession = editorPreviewSession ?? EditorPreviewSessionState()
        savedTextFingerprint = fingerprint
        currentTextFingerprint = fingerprint
    }

    var isDirty: Bool {
        currentTextFingerprint != savedTextFingerprint
    }

    func markSaved() {
        savedTextFingerprint = currentTextFingerprint
    }

    private static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

@MainActor
final class WorkspaceSession: ObservableObject {
    let rootURL: URL
    private let securityScopedAccess: SecurityScopedAccess?
    private let fileService: WorkspaceFileService

    @Published private(set) var openFiles: [OpenFileBuffer] = []
    @Published var activeFileID: OpenFileBuffer.ID?
    @Published var sidebarVisible = true
    @Published private(set) var rootNodes: [FileTreeNode] = []
    @Published private(set) var expandedDirectoryIDs: Set<FileTreeNode.ID> = []
    @Published private(set) var loadingDirectoryIDs: Set<FileTreeNode.ID> = []
    @Published private(set) var treeErrorDescription: String?
    private var childrenByDirectoryID: [FileTreeNode.ID: [FileTreeNode]] = [:]

    init(
        rootURL: URL,
        fileService: WorkspaceFileService = WorkspaceFileService()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        securityScopedAccess = nil
        self.fileService = fileService
    }

    init(
        reference: WorkspaceReference,
        fileService: WorkspaceFileService = WorkspaceFileService()
    ) throws {
        let access = try SecurityScopedAccess(reference: reference)
        rootURL = access.url
        securityScopedAccess = access
        self.fileService = fileService
    }

    var activeFile: OpenFileBuffer? {
        guard let activeFileID else {
            return nil
        }
        return openFiles.first { $0.id == activeFileID }
    }

    var visibleTreeRows: [WorkspaceTreeRow] {
        var rows: [WorkspaceTreeRow] = []
        appendVisibleRows(rootNodes, depth: 0, to: &rows)
        return rows
    }

    func loadRoot() async {
        guard rootNodes.isEmpty, !loadingDirectoryIDs.contains("") else {
            return
        }

        loadingDirectoryIDs.insert("")
        defer { loadingDirectoryIDs.remove("") }
        do {
            rootNodes = try await fileService.children(of: rootURL, within: rootURL)
            treeErrorDescription = nil
        } catch {
            treeErrorDescription = error.localizedDescription
        }
    }

    func toggleDirectory(_ node: FileTreeNode) async {
        guard node.isDirectory else {
            return
        }

        if expandedDirectoryIDs.remove(node.id) != nil {
            return
        }

        expandedDirectoryIDs.insert(node.id)
        guard childrenByDirectoryID[node.id] == nil else {
            return
        }

        loadingDirectoryIDs.insert(node.id)
        defer { loadingDirectoryIDs.remove(node.id) }
        do {
            let directoryURL = rootURL.appendingPathComponent(
                node.relativePath,
                isDirectory: true
            )
            childrenByDirectoryID[node.id] = try await fileService.children(
                of: directoryURL,
                within: rootURL
            )
            treeErrorDescription = nil
        } catch {
            expandedDirectoryIDs.remove(node.id)
            treeErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    func openFile(url: URL, text: String) -> OpenFileBuffer {
        let standardizedURL = url.standardizedFileURL
        if let existing = openFiles.first(where: { $0.url == standardizedURL }) {
            activeFileID = existing.id
            return existing
        }

        let buffer = OpenFileBuffer(url: standardizedURL, text: text)
        openFiles.append(buffer)
        activeFileID = buffer.id
        return buffer
    }

    func activateFile(id: OpenFileBuffer.ID) {
        guard openFiles.contains(where: { $0.id == id }) else {
            return
        }
        activeFileID = id
    }

    func closeDecision(for id: OpenFileBuffer.ID) -> WorkspaceBufferCloseDecision {
        guard let buffer = openFiles.first(where: { $0.id == id }) else {
            return .close
        }
        return buffer.isDirty ? .needsConfirmation : .close
    }

    @discardableResult
    func closeFile(id: OpenFileBuffer.ID, discardingChanges: Bool = false) -> Bool {
        guard let index = openFiles.firstIndex(where: { $0.id == id }) else {
            return true
        }
        guard discardingChanges || !openFiles[index].isDirty else {
            return false
        }

        let wasActive = activeFileID == id
        openFiles.remove(at: index)
        if wasActive {
            activeFileID = replacementActiveFileID(afterRemovingIndex: index)
        }
        return true
    }

    private func replacementActiveFileID(afterRemovingIndex index: Int) -> OpenFileBuffer.ID? {
        guard !openFiles.isEmpty else {
            return nil
        }
        return openFiles[min(index, openFiles.count - 1)].id
    }

    private func appendVisibleRows(
        _ nodes: [FileTreeNode],
        depth: Int,
        to rows: inout [WorkspaceTreeRow]
    ) {
        for node in nodes {
            rows.append(WorkspaceTreeRow(node: node, depth: depth))
            guard node.isDirectory,
                  expandedDirectoryIDs.contains(node.id),
                  let children = childrenByDirectoryID[node.id] else {
                continue
            }
            appendVisibleRows(children, depth: depth + 1, to: &rows)
        }
    }
}
