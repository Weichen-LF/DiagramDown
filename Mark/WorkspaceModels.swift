//
//  WorkspaceModels.swift
//  DiagramDown
//

import CryptoKit
import Combine
import Foundation

nonisolated struct WorkspaceReference: Codable, Hashable, Identifiable, Sendable {
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

nonisolated struct WorkspaceFileStamp: Equatable, Sendable {
    let modificationDate: Date
    let size: Int
}

nonisolated struct WorkspaceMarkdownSnapshot: Sendable {
    let text: String
    let stamp: WorkspaceFileStamp
}

nonisolated enum WorkspaceCreateItemKind: Equatable, Sendable {
    case markdownFile
    case directory
}

actor WorkspaceFileService {
    static let maximumEditableFileSize = 4 * 1_024 * 1_024

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

    func loadMarkdown(at fileURL: URL, within rootURL: URL) throws -> String {
        try markdownSnapshot(at: fileURL, within: rootURL).text
    }

    func markdownSnapshot(
        at fileURL: URL,
        within rootURL: URL
    ) throws -> WorkspaceMarkdownSnapshot {
        try validateMarkdownFile(fileURL, within: rootURL)
        let values = try fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
        ])
        if let fileSize = values.fileSize,
           fileSize > Self.maximumEditableFileSize {
            throw WorkspaceFileError.fileTooLarge
        }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= Self.maximumEditableFileSize else {
            throw WorkspaceFileError.fileTooLarge
        }
        do {
            return WorkspaceMarkdownSnapshot(
                text: try MarkdownFileCodec.decode(data),
                stamp: WorkspaceFileStamp(
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    size: data.count
                )
            )
        } catch {
            throw WorkspaceFileError.invalidUTF8
        }
    }

    func fileStamp(
        at fileURL: URL,
        within rootURL: URL
    ) throws -> WorkspaceFileStamp? {
        guard WorkspacePathPolicy.contains(fileURL, within: rootURL) else {
            throw WorkspaceFileError.outsideWorkspace
        }
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let values = try fileURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw WorkspaceFileError.unsupportedFileType
        }
        return WorkspaceFileStamp(
            modificationDate: values.contentModificationDate ?? .distantPast,
            size: values.fileSize ?? 0
        )
    }

    func saveMarkdown(_ text: String, to fileURL: URL, within rootURL: URL) throws {
        try validateMarkdownDestination(fileURL, within: rootURL)
        let data = try MarkdownFileCodec.encode(text)
        guard data.count <= Self.maximumEditableFileSize else {
            throw WorkspaceFileError.fileTooLarge
        }
        try data.write(to: fileURL, options: .atomic)
    }

    func createItem(
        named rawName: String,
        kind: WorkspaceCreateItemKind,
        in directoryURL: URL,
        within rootURL: URL
    ) throws -> URL {
        try validateDirectory(directoryURL, within: rootURL)
        let name = try validatedItemName(rawName)
        let finalName: String
        switch kind {
        case .markdownFile:
            finalName = ["md", "markdown"].contains(
                URL(fileURLWithPath: name).pathExtension.lowercased()
            ) ? name : "\(name).md"
        case .directory:
            finalName = name
        }
        let destination = directoryURL.appendingPathComponent(
            finalName,
            isDirectory: kind == .directory
        )
        guard WorkspacePathPolicy.contains(destination, within: rootURL),
              !fileManager.fileExists(atPath: destination.path) else {
            throw WorkspaceFileError.itemAlreadyExists
        }
        switch kind {
        case .markdownFile:
            try Data().write(to: destination, options: .withoutOverwriting)
        case .directory:
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: false
            )
        }
        return destination.standardizedFileURL
    }

    func renameItem(
        at sourceURL: URL,
        to rawName: String,
        within rootURL: URL
    ) throws -> URL {
        let name = try validatedItemName(rawName)
        if ["md", "markdown"].contains(sourceURL.pathExtension.lowercased()),
           !["md", "markdown"].contains(
            URL(fileURLWithPath: name).pathExtension.lowercased()
           ) {
            throw WorkspaceFileError.unsupportedFileType
        }
        let destination = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(name)
        return try moveItem(at: sourceURL, to: destination, within: rootURL)
    }

    func moveItem(
        at sourceURL: URL,
        into directoryURL: URL,
        within rootURL: URL
    ) throws -> URL {
        try validateDirectory(directoryURL, within: rootURL)
        let sourceValues = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        if sourceValues.isDirectory == true,
           WorkspacePathPolicy.contains(directoryURL, within: sourceURL) {
            throw WorkspaceFileError.invalidMoveDestination
        }
        let destination = directoryURL.appendingPathComponent(
            sourceURL.lastPathComponent
        )
        return try moveItem(at: sourceURL, to: destination, within: rootURL)
    }

    func deleteItem(at itemURL: URL, within rootURL: URL) throws {
        try validateExistingItem(itemURL, within: rootURL)
        guard itemURL.standardizedFileURL != rootURL.standardizedFileURL else {
            throw WorkspaceFileError.outsideWorkspace
        }
        try fileManager.removeItem(at: itemURL)
    }

    private func moveItem(
        at sourceURL: URL,
        to destinationURL: URL,
        within rootURL: URL
    ) throws -> URL {
        try validateExistingItem(sourceURL, within: rootURL)
        guard sourceURL.standardizedFileURL != rootURL.standardizedFileURL,
              WorkspacePathPolicy.contains(destinationURL, within: rootURL),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            throw WorkspaceFileError.itemAlreadyExists
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL.standardizedFileURL
    }

    private func validateMarkdownFile(_ fileURL: URL, within rootURL: URL) throws {
        guard WorkspacePathPolicy.contains(fileURL, within: rootURL) else {
            throw WorkspaceFileError.outsideWorkspace
        }
        guard ["md", "markdown"].contains(fileURL.pathExtension.lowercased()) else {
            throw WorkspaceFileError.unsupportedFileType
        }

        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        )
        guard values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw WorkspaceFileError.unsupportedFileType
        }
    }

    private func validateMarkdownDestination(
        _ fileURL: URL,
        within rootURL: URL
    ) throws {
        guard WorkspacePathPolicy.contains(fileURL, within: rootURL) else {
            throw WorkspaceFileError.outsideWorkspace
        }
        guard ["md", "markdown"].contains(fileURL.pathExtension.lowercased()) else {
            throw WorkspaceFileError.unsupportedFileType
        }
        if fileManager.fileExists(atPath: fileURL.path) {
            try validateMarkdownFile(fileURL, within: rootURL)
        } else {
            try validateDirectory(fileURL.deletingLastPathComponent(), within: rootURL)
        }
    }

    private func validateDirectory(_ url: URL, within rootURL: URL) throws {
        guard WorkspacePathPolicy.contains(url, within: rootURL) else {
            throw WorkspaceFileError.outsideWorkspace
        }
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw WorkspaceFileError.unsupportedFileType
        }
    }

    private func validateExistingItem(_ url: URL, within rootURL: URL) throws {
        guard WorkspacePathPolicy.contains(url, within: rootURL) else {
            throw WorkspaceFileError.outsideWorkspace
        }
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true,
              values.isDirectory == true || values.isRegularFile == true else {
            throw WorkspaceFileError.unsupportedFileType
        }
    }

    private func validatedItemName(_ rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(":") else {
            throw WorkspaceFileError.invalidItemName
        }
        return name
    }
}

enum WorkspaceFileError: LocalizedError, Equatable {
    case outsideWorkspace
    case unsupportedFileType
    case fileTooLarge
    case invalidUTF8
    case invalidItemName
    case itemAlreadyExists
    case externalConflict
    case invalidMoveDestination

    var errorDescription: String? {
        switch self {
        case .outsideWorkspace:
            "The file is outside the selected workspace."
        case .unsupportedFileType:
            "Only regular .md and .markdown files can be edited."
        case .fileTooLarge:
            "The file exceeds the 4 MB workspace editing limit."
        case .invalidUTF8:
            "The file is not valid UTF-8 text."
        case .invalidItemName:
            "The file or folder name is invalid."
        case .itemAlreadyExists:
            "An item with that name already exists."
        case .externalConflict:
            "The file changed on disk. Reload it or explicitly overwrite the external changes."
        case .invalidMoveDestination:
            "A folder cannot be moved into itself or one of its descendants."
        }
    }
}

enum WorkspaceBufferCloseDecision: Equatable {
    case close
    case needsConfirmation
}

enum WorkspaceExternalConflict: Equatable {
    case modified
    case deleted
}

@MainActor
final class OpenFileBuffer: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var url: URL
    let editorPreviewSession: EditorPreviewSessionState

    @Published var text: String {
        didSet {
            currentTextFingerprint = Self.fingerprint(text)
        }
    }

    @Published private(set) var savedTextFingerprint: String
    @Published var storedViewMode = DocumentViewMode.previewOnly.rawValue
    @Published private(set) var isSaving = false
    @Published private(set) var externalConflict: WorkspaceExternalConflict?
    private var currentTextFingerprint: String
    private(set) var lastObservedStamp: WorkspaceFileStamp?

    init(
        id: UUID = UUID(),
        url: URL,
        text: String,
        savedTextFingerprint: String? = nil,
        lastObservedStamp: WorkspaceFileStamp? = nil,
        storedViewMode: String = DocumentViewMode.previewOnly.rawValue,
        editorScrollPosition: ScrollSyncPosition = .initial,
        editorPreviewSession: EditorPreviewSessionState? = nil
    ) {
        let fingerprint = Self.fingerprint(text)
        self.id = id
        self.url = url.standardizedFileURL
        self.text = text
        let session = editorPreviewSession ?? EditorPreviewSessionState()
        session.editorScrollPosition = editorScrollPosition
        self.editorPreviewSession = session
        self.savedTextFingerprint = savedTextFingerprint ?? fingerprint
        self.lastObservedStamp = lastObservedStamp
        self.storedViewMode = storedViewMode
        currentTextFingerprint = fingerprint
    }

    var isDirty: Bool {
        currentTextFingerprint != savedTextFingerprint
    }

    func markSaved(stamp: WorkspaceFileStamp? = nil) {
        savedTextFingerprint = currentTextFingerprint
        lastObservedStamp = stamp
        externalConflict = nil
    }

    func markSaved(
        ifTextMatches savedText: String,
        stamp: WorkspaceFileStamp? = nil
    ) {
        guard text == savedText else {
            return
        }
        savedTextFingerprint = Self.fingerprint(savedText)
        lastObservedStamp = stamp
        externalConflict = nil
    }

    func setSaving(_ isSaving: Bool) {
        self.isSaving = isSaving
    }

    func updateObservedStamp(_ stamp: WorkspaceFileStamp?) {
        lastObservedStamp = stamp
    }

    func applyExternalText(_ text: String, stamp: WorkspaceFileStamp) {
        self.text = text
        markSaved(stamp: stamp)
    }

    func recordExternalConflict(_ conflict: WorkspaceExternalConflict) {
        externalConflict = conflict
    }

    func clearExternalConflict() {
        externalConflict = nil
    }

    func move(to url: URL) {
        self.url = url.standardizedFileURL
    }

    static func fingerprint(_ text: String) -> String {
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
    private let workspaceID: UUID?
    private let recoveryStore: WorkspaceRecoveryStore?
    private var recoverySaveTask: Task<Void, Never>?
    private var externalChangeTask: Task<Void, Never>?
    private var bufferObservers: [OpenFileBuffer.ID: AnyCancellable] = [:]
    private var isRestoringRecovery = false

    @Published private(set) var openFiles: [OpenFileBuffer] = []
    @Published var activeFileID: OpenFileBuffer.ID?
    @Published var sidebarVisible = true
    @Published private(set) var sidebarWidth: Double = 260
    @Published private(set) var restoredWindowFrame: WorkspaceWindowFrame?
    @Published private(set) var rootNodes: [FileTreeNode] = []
    @Published private(set) var expandedDirectoryIDs: Set<FileTreeNode.ID> = []
    @Published private(set) var loadingDirectoryIDs: Set<FileTreeNode.ID> = []
    @Published private(set) var openingFileIDs: Set<FileTreeNode.ID> = []
    @Published private(set) var treeErrorDescription: String?
    @Published private(set) var fileErrorDescription: String?
    private var childrenByDirectoryID: [FileTreeNode.ID: [FileTreeNode]] = [:]

    init(
        rootURL: URL,
        fileService: WorkspaceFileService = WorkspaceFileService(),
        recoverySnapshot: WorkspaceRecoverySnapshot? = nil
    ) {
        self.rootURL = rootURL.standardizedFileURL
        securityScopedAccess = nil
        self.fileService = fileService
        workspaceID = recoverySnapshot?.workspaceID
        recoveryStore = nil
        if let recoverySnapshot {
            restore(recoverySnapshot)
        }
    }

    init(
        reference: WorkspaceReference,
        fileService: WorkspaceFileService = WorkspaceFileService(),
        recoveryStore: WorkspaceRecoveryStore = .shared
    ) async throws {
        let access = try SecurityScopedAccess(reference: reference)
        rootURL = access.url
        securityScopedAccess = access
        self.fileService = fileService
        workspaceID = reference.id
        self.recoveryStore = recoveryStore
        WorkspaceLaunchRestoration.shared.remember(
            WorkspaceReference(
                id: reference.id,
                bookmarkData: access.refreshedBookmarkData ?? reference.bookmarkData
            )
        )
        if let snapshot = try await recoveryStore.load(workspaceID: reference.id) {
            restore(snapshot)
            await reloadCleanRecoveredFiles()
        }
    }

    deinit {
        recoverySaveTask?.cancel()
        externalChangeTask?.cancel()
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
            await loadRecoveredExpandedDirectories()
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
            scheduleRecoverySave()
            return
        }

        expandedDirectoryIDs.insert(node.id)
        scheduleRecoverySave()
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
            scheduleRecoverySave()
            treeErrorDescription = error.localizedDescription
        }
    }

    func openFile(_ node: FileTreeNode) async {
        guard node.canOpen else {
            return
        }

        let fileURL = rootURL.appendingPathComponent(node.relativePath)
        if let existing = openFiles.first(where: { $0.url == fileURL.standardizedFileURL }) {
            activeFileID = existing.id
            scheduleRecoverySave()
            return
        }
        guard openingFileIDs.insert(node.id).inserted else {
            return
        }
        defer { openingFileIDs.remove(node.id) }

        do {
            let snapshot = try await fileService.markdownSnapshot(
                at: fileURL,
                within: rootURL
            )
            openFile(
                url: fileURL,
                text: snapshot.text,
                stamp: snapshot.stamp
            )
            fileErrorDescription = nil
        } catch {
            fileErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    func saveFile(
        id: OpenFileBuffer.ID,
        overwritingExternalChanges: Bool = false
    ) async -> Bool {
        guard let buffer = openFiles.first(where: { $0.id == id }),
              !buffer.isSaving else {
            return false
        }

        buffer.setSaving(true)
        defer { buffer.setSaving(false) }
        let textToSave = buffer.text
        do {
            if !overwritingExternalChanges {
                if buffer.externalConflict != nil {
                    throw WorkspaceFileError.externalConflict
                }
                guard try await fileService.fileStamp(
                    at: buffer.url,
                    within: rootURL
                ) != nil else {
                    buffer.recordExternalConflict(.deleted)
                    throw WorkspaceFileError.externalConflict
                }
                let diskSnapshot = try await fileService.markdownSnapshot(
                    at: buffer.url,
                    within: rootURL
                )
                if OpenFileBuffer.fingerprint(diskSnapshot.text)
                    != buffer.savedTextFingerprint {
                    buffer.updateObservedStamp(diskSnapshot.stamp)
                    buffer.recordExternalConflict(.modified)
                    throw WorkspaceFileError.externalConflict
                }
            }
            try await fileService.saveMarkdown(
                textToSave,
                to: buffer.url,
                within: rootURL
            )
            let stamp = try await fileService.fileStamp(
                at: buffer.url,
                within: rootURL
            )
            buffer.markSaved(ifTextMatches: textToSave, stamp: stamp)
            fileErrorDescription = nil
            return true
        } catch {
            fileErrorDescription = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveActiveFile() async -> Bool {
        guard let activeFileID else {
            return false
        }
        return await saveFile(id: activeFileID)
    }

    @discardableResult
    func saveAllDirtyFiles() async -> Bool {
        let dirtyFileIDs = openFiles.filter(\.isDirty).map(\.id)
        for id in dirtyFileIDs {
            guard await saveFile(id: id) else {
                return false
            }
        }

        guard !openFiles.contains(where: \.isDirty) else {
            fileErrorDescription = "A file changed while the workspace was saving. Save again."
            return false
        }
        return true
    }

    func clearFileError() {
        fileErrorDescription = nil
    }

    @discardableResult
    func openFile(
        url: URL,
        text: String,
        stamp: WorkspaceFileStamp? = nil
    ) -> OpenFileBuffer {
        let standardizedURL = url.standardizedFileURL
        if let existing = openFiles.first(where: { $0.url == standardizedURL }) {
            activeFileID = existing.id
            scheduleRecoverySave()
            return existing
        }

        let buffer = OpenFileBuffer(
            url: standardizedURL,
            text: text,
            lastObservedStamp: stamp
        )
        openFiles.append(buffer)
        observe(buffer)
        activeFileID = buffer.id
        scheduleRecoverySave()
        return buffer
    }

    func activateFile(id: OpenFileBuffer.ID) {
        guard openFiles.contains(where: { $0.id == id }) else {
            return
        }
        activeFileID = id
        scheduleRecoverySave()
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
        bufferObservers[id] = nil
        if wasActive {
            activeFileID = replacementActiveFileID(afterRemovingIndex: index)
        }
        scheduleRecoverySave()
        return true
    }

    func setSidebarVisible(_ isVisible: Bool) {
        guard sidebarVisible != isVisible else {
            return
        }
        sidebarVisible = isVisible
        scheduleRecoverySave()
    }

    func setSidebarWidth(_ width: Double) {
        let clamped = min(max(width, 190), 420)
        guard abs(sidebarWidth - clamped) > 0.5 else {
            return
        }
        sidebarWidth = clamped
        scheduleRecoverySave()
    }

    func setWindowFrame(_ frame: WorkspaceWindowFrame) {
        guard frame.width >= 760, frame.height >= 460 else {
            return
        }
        restoredWindowFrame = frame
        scheduleRecoverySave()
    }

    func startMonitoringExternalChanges() {
        guard externalChangeTask == nil else {
            return
        }
        externalChangeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else {
                    return
                }
                await self?.checkForExternalChanges()
            }
        }
    }

    func stopMonitoringExternalChanges() {
        externalChangeTask?.cancel()
        externalChangeTask = nil
    }

    func checkForExternalChanges() async {
        for buffer in openFiles where !buffer.isSaving {
            do {
                guard let stamp = try await fileService.fileStamp(
                    at: buffer.url,
                    within: rootURL
                ) else {
                    buffer.updateObservedStamp(nil)
                    buffer.recordExternalConflict(.deleted)
                    continue
                }
                guard stamp != buffer.lastObservedStamp else {
                    continue
                }
                let snapshot = try await fileService.markdownSnapshot(
                    at: buffer.url,
                    within: rootURL
                )
                let diskFingerprint = OpenFileBuffer.fingerprint(snapshot.text)
                buffer.updateObservedStamp(snapshot.stamp)
                if diskFingerprint == buffer.savedTextFingerprint {
                    buffer.clearExternalConflict()
                } else if buffer.isDirty {
                    buffer.recordExternalConflict(.modified)
                } else {
                    buffer.applyExternalText(snapshot.text, stamp: snapshot.stamp)
                }
            } catch {
                buffer.recordExternalConflict(.deleted)
            }
        }
    }

    @discardableResult
    func reloadFileFromDisk(id: OpenFileBuffer.ID) async -> Bool {
        guard let buffer = openFiles.first(where: { $0.id == id }) else {
            return false
        }
        do {
            let snapshot = try await fileService.markdownSnapshot(
                at: buffer.url,
                within: rootURL
            )
            buffer.applyExternalText(snapshot.text, stamp: snapshot.stamp)
            fileErrorDescription = nil
            return true
        } catch {
            fileErrorDescription = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func overwriteFile(id: OpenFileBuffer.ID) async -> Bool {
        await saveFile(id: id, overwritingExternalChanges: true)
    }

    func createItem(
        named name: String,
        kind: WorkspaceCreateItemKind,
        in directoryNode: FileTreeNode?
    ) async {
        let directoryURL: URL
        if let directoryNode {
            guard directoryNode.isDirectory else {
                return
            }
            directoryURL = rootURL.appendingPathComponent(
                directoryNode.relativePath,
                isDirectory: true
            )
        } else {
            directoryURL = rootURL
        }
        do {
            let createdURL = try await fileService.createItem(
                named: name,
                kind: kind,
                in: directoryURL,
                within: rootURL
            )
            await reloadTree()
            if kind == .markdownFile {
                let snapshot = try await fileService.markdownSnapshot(
                    at: createdURL,
                    within: rootURL
                )
                openFile(
                    url: createdURL,
                    text: snapshot.text,
                    stamp: snapshot.stamp
                )
            }
            fileErrorDescription = nil
        } catch {
            fileErrorDescription = error.localizedDescription
        }
    }

    func renameItem(_ node: FileTreeNode, to newName: String) async {
        let sourceURL = rootURL.appendingPathComponent(
            node.relativePath,
            isDirectory: node.isDirectory
        )
        do {
            let destinationURL = try await fileService.renameItem(
                at: sourceURL,
                to: newName,
                within: rootURL
            )
            updateOpenFileURLs(from: sourceURL, to: destinationURL)
            await reloadTree()
            fileErrorDescription = nil
        } catch {
            fileErrorDescription = error.localizedDescription
        }
    }

    func moveItem(_ node: FileTreeNode, into directoryURL: URL) async {
        let sourceURL = rootURL.appendingPathComponent(
            node.relativePath,
            isDirectory: node.isDirectory
        )
        do {
            let destinationURL = try await fileService.moveItem(
                at: sourceURL,
                into: directoryURL,
                within: rootURL
            )
            updateOpenFileURLs(from: sourceURL, to: destinationURL)
            await reloadTree()
            fileErrorDescription = nil
        } catch {
            fileErrorDescription = error.localizedDescription
        }
    }

    func deleteItem(_ node: FileTreeNode) async {
        let itemURL = rootURL.appendingPathComponent(
            node.relativePath,
            isDirectory: node.isDirectory
        )
        do {
            try await fileService.deleteItem(at: itemURL, within: rootURL)
            let affectedIDs = openFiles
                .filter { WorkspacePathPolicy.contains($0.url, within: itemURL) }
                .map(\.id)
            for id in affectedIDs {
                closeFile(id: id, discardingChanges: true)
            }
            await reloadTree()
            fileErrorDescription = nil
        } catch {
            fileErrorDescription = error.localizedDescription
        }
    }

    func persistRecoveryNow() async {
        recoverySaveTask?.cancel()
        recoverySaveTask = nil
        await saveRecoverySnapshot()
    }

    private func replacementActiveFileID(afterRemovingIndex index: Int) -> OpenFileBuffer.ID? {
        guard !openFiles.isEmpty else {
            return nil
        }
        return openFiles[min(index, openFiles.count - 1)].id
    }

    private func reloadTree() async {
        rootNodes = []
        childrenByDirectoryID = [:]
        loadingDirectoryIDs = []
        openingFileIDs = []
        await loadRoot()
    }

    private func updateOpenFileURLs(from sourceURL: URL, to destinationURL: URL) {
        let standardizedSource = sourceURL.standardizedFileURL
        for buffer in openFiles {
            guard let suffix = WorkspacePathPolicy.relativePath(
                of: buffer.url,
                within: standardizedSource
            ) else {
                continue
            }
            let newURL = suffix.isEmpty
                ? destinationURL
                : destinationURL.appendingPathComponent(suffix)
            buffer.move(to: newURL)
        }
        expandedDirectoryIDs = []
        scheduleRecoverySave()
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

    private func restore(_ snapshot: WorkspaceRecoverySnapshot) {
        isRestoringRecovery = true
        defer { isRestoringRecovery = false }

        sidebarVisible = snapshot.sidebarVisible
        sidebarWidth = min(max(snapshot.sidebarWidth ?? 260, 190), 420)
        restoredWindowFrame = snapshot.windowFrame
        expandedDirectoryIDs = Set(
            snapshot.expandedDirectoryIDs.filter(Self.isSafeRelativePath)
        )
        openFiles = snapshot.openFiles.compactMap { recovered in
            guard Self.isSafeRelativePath(recovered.relativePath) else {
                return nil
            }
            let url = rootURL.appendingPathComponent(recovered.relativePath)
            guard WorkspacePathPolicy.contains(url, within: rootURL) else {
                return nil
            }
            let progress = recovered.editorScrollProgress.isFinite
                ? min(max(recovered.editorScrollProgress, 0), 1)
                : 0
            return OpenFileBuffer(
                id: recovered.id,
                url: url,
                text: recovered.text,
                savedTextFingerprint: recovered.savedTextFingerprint,
                storedViewMode: DocumentViewMode(
                    rawValue: recovered.storedViewMode
                )?.rawValue ?? DocumentViewMode.previewOnly.rawValue,
                editorScrollPosition: ScrollSyncPosition(
                    sourceLine: max(recovered.editorSourceLine, 1),
                    progress: progress,
                    generation: 0
                )
            )
        }
        openFiles.forEach(observe)
        activeFileID = openFiles.contains(where: { $0.id == snapshot.activeFileID })
            ? snapshot.activeFileID
            : openFiles.last?.id
    }

    private func makeRecoverySnapshot() -> WorkspaceRecoverySnapshot? {
        guard let workspaceID else {
            return nil
        }
        let files = openFiles.compactMap { buffer -> WorkspaceBufferRecoverySnapshot? in
            guard let relativePath = WorkspacePathPolicy.relativePath(
                of: buffer.url,
                within: rootURL
            ), Self.isSafeRelativePath(relativePath) else {
                return nil
            }
            let scroll = buffer.editorPreviewSession.editorScrollPosition
            return WorkspaceBufferRecoverySnapshot(
                id: buffer.id,
                relativePath: relativePath,
                text: buffer.text,
                savedTextFingerprint: buffer.savedTextFingerprint,
                storedViewMode: buffer.storedViewMode,
                editorSourceLine: scroll.sourceLine,
                editorScrollProgress: scroll.progress
            )
        }
        return WorkspaceRecoverySnapshot(
            workspaceID: workspaceID,
            openFiles: files,
            activeFileID: activeFileID,
            sidebarVisible: sidebarVisible,
            sidebarWidth: sidebarWidth,
            windowFrame: restoredWindowFrame,
            expandedDirectoryIDs: expandedDirectoryIDs
        )
    }

    private func observe(_ buffer: OpenFileBuffer) {
        bufferObservers[buffer.id] = buffer.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.scheduleRecoverySave()
            }
        }
    }

    private func scheduleRecoverySave() {
        guard !isRestoringRecovery, recoveryStore != nil else {
            return
        }
        recoverySaveTask?.cancel()
        recoverySaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else {
                return
            }
            await self?.saveRecoverySnapshot()
        }
    }

    private func saveRecoverySnapshot() async {
        guard let recoveryStore,
              let snapshot = makeRecoverySnapshot() else {
            return
        }
        do {
            try await recoveryStore.save(snapshot)
        } catch {
            fileErrorDescription = "Recovery data could not be saved: \(error.localizedDescription)"
        }
    }

    private func loadRecoveredExpandedDirectories() async {
        let recoveredIDs = expandedDirectoryIDs.sorted {
            $0.split(separator: "/").count < $1.split(separator: "/").count
        }
        for directoryID in recoveredIDs {
            guard childrenByDirectoryID[directoryID] == nil,
                  Self.isSafeRelativePath(directoryID) else {
                continue
            }
            let directoryURL = rootURL.appendingPathComponent(
                directoryID,
                isDirectory: true
            )
            do {
                childrenByDirectoryID[directoryID] = try await fileService.children(
                    of: directoryURL,
                    within: rootURL
                )
            } catch {
                expandedDirectoryIDs.remove(directoryID)
            }
        }
    }

    private func reloadCleanRecoveredFiles() async {
        isRestoringRecovery = true
        defer { isRestoringRecovery = false }

        for buffer in openFiles where !buffer.isDirty {
            do {
                let snapshot = try await fileService.markdownSnapshot(
                    at: buffer.url,
                    within: rootURL
                )
                buffer.applyExternalText(snapshot.text, stamp: snapshot.stamp)
            } catch {
                // Keep the recovered copy available if the file was moved or deleted.
            }
        }
    }

    nonisolated private static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }
}
