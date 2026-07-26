import Foundation
import XCTest
@testable import DiagramDown

final class PreviewZoomTests: XCTestCase {
    func testClampingUsesSupportedBounds() {
        XCTAssertEqual(PreviewZoom.clamped(PreviewZoom.minimum - 1), PreviewZoom.minimum)
        XCTAssertEqual(PreviewZoom.clamped(125), 125)
        XCTAssertEqual(PreviewZoom.clamped(PreviewZoom.maximum + 1), PreviewZoom.maximum)
    }

    func testScalingRoundsAndClampsTrackpadValues() {
        XCTAssertEqual(PreviewZoom.scaled(100, by: 1.126), 113)
        XCTAssertEqual(PreviewZoom.scaled(100, by: 0.874), 87)
        XCTAssertEqual(PreviewZoom.scaled(190, by: 2), PreviewZoom.maximum)
        XCTAssertEqual(PreviewZoom.scaled(60, by: 0.1), PreviewZoom.minimum)
        XCTAssertEqual(PreviewZoom.scaled(100, by: .infinity), 100)
    }

    func testMenuValuesAreOrderedAndContainDefault() {
        XCTAssertEqual(PreviewZoom.menuValues, PreviewZoom.menuValues.sorted())
        XCTAssertTrue(PreviewZoom.menuValues.contains(PreviewZoom.defaultValue))
        XCTAssertTrue(PreviewZoom.menuValues.allSatisfy {
            (PreviewZoom.minimum...PreviewZoom.maximum).contains($0)
        })
    }
}

final class DocumentViewModeTests: XCTestCase {
    func testAllDocumentLayoutsRemainAvailable() {
        XCTAssertEqual(
            DocumentViewMode.allCases.map(\.rawValue),
            ["editorOnly", "editorAndPreview", "previewOnly"]
        )
    }

    func testPreviewVisibilityMatchesLayout() {
        XCTAssertFalse(DocumentViewMode.editorOnly.showsPreview)
        XCTAssertTrue(DocumentViewMode.editorAndPreview.showsPreview)
        XCTAssertTrue(DocumentViewMode.previewOnly.showsPreview)
    }

    func testEveryLayoutHasToolbarMetadata() {
        for mode in DocumentViewMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.systemImage.isEmpty)
        }
    }
}

@MainActor
final class WorkspaceModelTests: XCTestCase {
    func testRecoverySnapshotRestoresTabsDirtyTextAndWorkspaceState() async {
        let root = URL(fileURLWithPath: "/tmp/project")
        let firstID = UUID()
        let secondID = UUID()
        let windowFrame = WorkspaceWindowFrame(
            x: 120,
            y: 80,
            width: 1_280,
            height: 820
        )
        let snapshot = WorkspaceRecoverySnapshot(
            workspaceID: UUID(),
            openFiles: [
                WorkspaceBufferRecoverySnapshot(
                    id: firstID,
                    relativePath: "README.md",
                    text: "# Unsaved edit\n",
                    savedTextFingerprint: OpenFileBuffer.fingerprint("# Saved\n"),
                    storedViewMode: DocumentViewMode.editorOnly.rawValue,
                    editorSourceLine: 18,
                    editorScrollProgress: 0.4
                ),
                WorkspaceBufferRecoverySnapshot(
                    id: secondID,
                    relativePath: "docs/notes.markdown",
                    text: "Notes\n",
                    savedTextFingerprint: OpenFileBuffer.fingerprint("Notes\n"),
                    storedViewMode: DocumentViewMode.previewOnly.rawValue,
                    editorSourceLine: 3,
                    editorScrollProgress: 0.1
                ),
            ],
            activeFileID: firstID,
            sidebarVisible: false,
            sidebarWidth: 318,
            windowFrame: windowFrame,
            expandedDirectoryIDs: ["docs"]
        )

        let session = WorkspaceSession(rootURL: root, recoverySnapshot: snapshot)

        XCTAssertEqual(session.openFiles.map(\.id), [firstID, secondID])
        XCTAssertEqual(session.activeFileID, firstID)
        XCTAssertEqual(session.activeFile?.text, "# Unsaved edit\n")
        XCTAssertTrue(session.activeFile?.isDirty == true)
        XCTAssertEqual(session.activeFile?.storedViewMode, DocumentViewMode.editorOnly.rawValue)
        XCTAssertEqual(session.activeFile?.editorPreviewSession.editorScrollPosition.sourceLine, 18)
        XCTAssertEqual(session.activeFile?.editorPreviewSession.editorScrollPosition.progress, 0.4)
        XCTAssertFalse(session.sidebarVisible)
        XCTAssertEqual(session.sidebarWidth, 318)
        XCTAssertEqual(session.restoredWindowFrame, windowFrame)
        XCTAssertEqual(session.expandedDirectoryIDs, ["docs"])
    }

    func testRecoverySnapshotRejectsUnsafeRelativePaths() async {
        let snapshot = WorkspaceRecoverySnapshot(
            workspaceID: UUID(),
            openFiles: [
                WorkspaceBufferRecoverySnapshot(
                    id: UUID(),
                    relativePath: "../outside.md",
                    text: "private",
                    savedTextFingerprint: OpenFileBuffer.fingerprint("private"),
                    storedViewMode: DocumentViewMode.editorAndPreview.rawValue,
                    editorSourceLine: 1,
                    editorScrollProgress: 0
                ),
            ],
            activeFileID: nil,
            sidebarVisible: true,
            expandedDirectoryIDs: ["../outside"]
        )

        let session = WorkspaceSession(
            rootURL: URL(fileURLWithPath: "/tmp/project"),
            recoverySnapshot: snapshot
        )

        XCTAssertTrue(session.openFiles.isEmpty)
        XCTAssertTrue(session.expandedDirectoryIDs.isEmpty)
    }

    func testEditingAndSavingUpdatesDirtyState() async {
        let buffer = OpenFileBuffer(
            url: URL(fileURLWithPath: "/tmp/README.md"),
            text: "# Original\n"
        )

        XCTAssertFalse(buffer.isDirty)
        buffer.text = "# Changed\n"
        XCTAssertTrue(buffer.isDirty)
        buffer.markSaved()
        XCTAssertFalse(buffer.isDirty)
        buffer.text = "# Original\n"
        XCTAssertTrue(buffer.isDirty)
    }

    func testOpeningSameStandardizedURLActivatesExistingBuffer() async {
        let session = WorkspaceSession(rootURL: URL(fileURLWithPath: "/tmp/project"))
        let first = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/docs/../README.md"),
            text: "first"
        )
        let second = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/README.md"),
            text: "ignored"
        )

        XCTAssertTrue(first === second)
        XCTAssertEqual(session.openFiles.count, 1)
        XCTAssertEqual(session.activeFileID, first.id)
        XCTAssertEqual(first.text, "first")
    }

    func testBuffersKeepIndependentEditorPreviewSessions() async {
        let session = WorkspaceSession(rootURL: URL(fileURLWithPath: "/tmp/project"))
        let first = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/first.md"),
            text: "first"
        )
        let second = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/second.md"),
            text: "second"
        )

        XCTAssertFalse(first.editorPreviewSession === second.editorPreviewSession)
        first.editorPreviewSession.editorScrollTarget = ScrollSyncTarget(
            sourceLine: 12,
            progress: 0.5,
            usesProgressFallback: false,
            animated: false,
            generation: 1
        )
        XCTAssertEqual(second.editorPreviewSession.editorScrollTarget.sourceLine, 1)
    }

    func testDirtyBufferCannotCloseWithoutExplicitDiscard() async {
        let session = WorkspaceSession(rootURL: URL(fileURLWithPath: "/tmp/project"))
        let first = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/first.md"),
            text: "first"
        )
        let second = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/second.md"),
            text: "second"
        )
        first.text = "changed"

        XCTAssertEqual(session.closeDecision(for: first.id), .needsConfirmation)
        XCTAssertFalse(session.closeFile(id: first.id))
        XCTAssertEqual(session.openFiles.count, 2)
        XCTAssertTrue(session.closeFile(id: first.id, discardingChanges: true))
        XCTAssertEqual(session.openFiles.map(\.id), [second.id])
        XCTAssertEqual(session.activeFileID, second.id)
    }

    func testClosingActiveCleanBufferSelectsAdjacentTab() async {
        let session = WorkspaceSession(rootURL: URL(fileURLWithPath: "/tmp/project"))
        let first = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/first.md"),
            text: "first"
        )
        let second = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/second.md"),
            text: "second"
        )
        let third = session.openFile(
            url: URL(fileURLWithPath: "/tmp/project/third.md"),
            text: "third"
        )
        session.activateFile(id: second.id)

        XCTAssertTrue(session.closeFile(id: second.id))
        XCTAssertEqual(session.openFiles.map(\.id), [first.id, third.id])
        XCTAssertEqual(session.activeFileID, third.id)
    }

    func testPathContainmentUsesComponentsInsteadOfStringPrefixes() {
        let root = URL(fileURLWithPath: "/tmp/project")

        XCTAssertTrue(
            WorkspacePathPolicy.contains(
                URL(fileURLWithPath: "/tmp/project/docs/README.md"),
                within: root
            )
        )
        XCTAssertFalse(
            WorkspacePathPolicy.contains(
                URL(fileURLWithPath: "/tmp/project-secret/README.md"),
                within: root
            )
        )
        XCTAssertFalse(
            WorkspacePathPolicy.contains(
                URL(fileURLWithPath: "/tmp/project/../outside.md"),
                within: root
            )
        )
    }

    func testDirectoryServiceSortsFoldersFirstAndRecognizesMarkdown() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("docs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("plain".utf8).write(to: root.appendingPathComponent("z.txt"))
        try Data("# Markdown".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("# Markdown".utf8).write(to: root.appendingPathComponent("notes.markdown"))
        defer { try? FileManager.default.removeItem(at: root) }

        let nodes = try await WorkspaceFileService().children(of: root, within: root)

        XCTAssertEqual(nodes.map(\.name), ["docs", "notes.markdown", "README.md", "z.txt"])
        XCTAssertEqual(
            nodes.map(\.kind),
            [.directory, .markdownFile, .markdownFile, .otherFile]
        )
    }

    func testDirectoryServiceDoesNotExposeSymlinks() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let nodes = try await WorkspaceFileService().children(of: root, within: root)

        XCTAssertTrue(nodes.isEmpty)
    }

    func testFileServiceLoadsAndAtomicallySavesUTF8Markdown() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("README.md")
        try Data("# Original\n".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFileService()

        let original = try await service.loadMarkdown(at: fileURL, within: root)
        XCTAssertEqual(original, "# Original\n")
        try await service.saveMarkdown("# 已保存\n", to: fileURL, within: root)
        let saved = try await service.loadMarkdown(at: fileURL, within: root)
        XCTAssertEqual(saved, "# 已保存\n")
    }

    func testFileServiceRejectsUnsupportedAndInvalidUTF8Files() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let textURL = root.appendingPathComponent("notes.txt")
        let markdownURL = root.appendingPathComponent("invalid.md")
        try Data("text".utf8).write(to: textURL)
        try Data([0xC3, 0x28]).write(to: markdownURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFileService()

        do {
            _ = try await service.loadMarkdown(at: textURL, within: root)
            XCTFail("Expected an unsupported file type error")
        } catch {
            XCTAssertEqual(error as? WorkspaceFileError, .unsupportedFileType)
        }

        do {
            _ = try await service.loadMarkdown(at: markdownURL, within: root)
            XCTFail("Expected an invalid UTF-8 error")
        } catch {
            XCTAssertEqual(error as? WorkspaceFileError, .invalidUTF8)
        }
    }

    func testFileServiceCreatesRenamesMovesAndDeletesWorkspaceItems() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WorkspaceFileService()

        let docs = try await service.createItem(
            named: "docs",
            kind: .directory,
            in: root,
            within: root
        )
        let draft = try await service.createItem(
            named: "Draft",
            kind: .markdownFile,
            in: root,
            within: root
        )
        XCTAssertEqual(draft.lastPathComponent, "Draft.md")

        let renamed = try await service.renameItem(
            at: draft,
            to: "Guide.markdown",
            within: root
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.path))

        let moved = try await service.moveItem(at: renamed, into: docs, within: root)
        XCTAssertEqual(moved.lastPathComponent, "Guide.markdown")
        XCTAssertEqual(moved.deletingLastPathComponent(), docs)

        let textFile = root.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: textFile)
        let renamedTextFile = try await service.renameItem(
            at: textFile,
            to: "archive.txt",
            within: root
        )
        XCTAssertEqual(renamedTextFile.lastPathComponent, "archive.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedTextFile.path))

        try await service.deleteItem(at: moved, within: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.path))
    }

    func testCleanBufferReloadsWhenFileChangesExternally() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data("original".utf8).write(to: fileURL)
        let session = WorkspaceSession(rootURL: root)
        let buffer = session.openFile(url: fileURL, text: "original")

        try Data("changed outside".utf8).write(to: fileURL)
        await session.checkForExternalChanges()

        XCTAssertEqual(buffer.text, "changed outside")
        XCTAssertFalse(buffer.isDirty)
        XCTAssertNil(buffer.externalConflict)
    }

    func testDirtyBufferRequiresExplicitConflictResolution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data("original".utf8).write(to: fileURL)
        let session = WorkspaceSession(rootURL: root)
        let buffer = session.openFile(url: fileURL, text: "original")
        buffer.text = "editor change"

        try Data("disk change".utf8).write(to: fileURL)
        await session.checkForExternalChanges()

        XCTAssertEqual(buffer.externalConflict, .modified)
        let savedWithoutResolution = await session.saveActiveFile()
        XCTAssertFalse(savedWithoutResolution)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "disk change")
        let overwritten = await session.overwriteFile(id: buffer.id)
        XCTAssertTrue(overwritten)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "editor change")
        XCTAssertNil(buffer.externalConflict)
    }

    func testDeletedFileKeepsEditorCopyUntilUserResolvesConflict() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("README.md")
        try Data("original".utf8).write(to: fileURL)
        let session = WorkspaceSession(rootURL: root)
        let buffer = session.openFile(url: fileURL, text: "original")

        try FileManager.default.removeItem(at: fileURL)
        await session.checkForExternalChanges()

        XCTAssertEqual(buffer.externalConflict, .deleted)
        XCTAssertEqual(buffer.text, "original")
        let recreated = await session.overwriteFile(id: buffer.id)
        XCTAssertTrue(recreated)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "original")
    }

    func testSavingActiveBufferUpdatesDiskAndDirtyState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("README.md")
        try Data("# Original\n".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(rootURL: root)
        let buffer = session.openFile(url: fileURL, text: "# Original\n")
        buffer.text = "# Changed\n"

        XCTAssertTrue(buffer.isDirty)
        let didSave = await session.saveActiveFile()
        XCTAssertTrue(didSave)
        XCTAssertFalse(buffer.isDirty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Changed\n")
    }

    func testTreeNodeOpensMarkdownIntoActiveBuffer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("README.md")
        try Data("# Workspace\n".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(rootURL: root)

        await session.loadRoot()
        let node = try XCTUnwrap(session.rootNodes.first)
        await session.openFile(node)

        XCTAssertEqual(session.openFiles.count, 1)
        XCTAssertEqual(session.activeFile?.url, fileURL.standardizedFileURL)
        XCTAssertEqual(session.activeFile?.text, "# Workspace\n")
    }

    func testSaveAllWritesEveryDirtyBuffer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let firstURL = root.appendingPathComponent("first.md")
        let secondURL = root.appendingPathComponent("second.md")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = WorkspaceSession(rootURL: root)
        let first = session.openFile(url: firstURL, text: "first")
        let second = session.openFile(url: secondURL, text: "second")
        first.text = "updated first"
        second.text = "updated second"

        let didSave = await session.saveAllDirtyFiles()

        XCTAssertTrue(didSave)
        XCTAssertFalse(first.isDirty)
        XCTAssertFalse(second.isDirty)
        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "updated first")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "updated second")
    }
}

final class WorkspaceRecoveryStoreTests: XCTestCase {
    func testCorruptSnapshotDoesNotPreventWorkspaceFromOpening() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let workspaceID = UUID()
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent(
                "\(workspaceID.uuidString.lowercased()).json"
            )
        )
        let store = WorkspaceRecoveryStore(directoryURL: directory)

        let loadedSnapshot = try await store.load(workspaceID: workspaceID)
        XCTAssertNil(loadedSnapshot)
    }

    func testSnapshotIsWrittenAtomicallyAndRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WorkspaceRecoveryStore(directoryURL: directory)
        let workspaceID = UUID()
        let snapshot = WorkspaceRecoverySnapshot(
            workspaceID: workspaceID,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            openFiles: [
                WorkspaceBufferRecoverySnapshot(
                    id: UUID(),
                    relativePath: "README.md",
                    text: "# Recovered\n",
                    savedTextFingerprint: "saved-fingerprint",
                    storedViewMode: DocumentViewMode.editorAndPreview.rawValue,
                    editorSourceLine: 5,
                    editorScrollProgress: 0.25
                ),
            ],
            activeFileID: nil,
            sidebarVisible: true,
            sidebarWidth: 304,
            windowFrame: WorkspaceWindowFrame(
                x: 40,
                y: 60,
                width: 1_100,
                height: 760
            ),
            expandedDirectoryIDs: ["docs"]
        )

        try await store.save(snapshot)

        let loadedSnapshot = try await store.load(workspaceID: workspaceID)
        XCTAssertEqual(loadedSnapshot, snapshot)
        try await store.remove(workspaceID: workspaceID)
        let removedSnapshot = try await store.load(workspaceID: workspaceID)
        XCTAssertNil(removedSnapshot)
    }
}

@MainActor
final class WorkspaceLaunchRestorationTests: XCTestCase {
    private final class MemoryStorage: WorkspaceLaunchStorage {
        private var values: [String: Any] = [:]

        func data(forKey defaultName: String) -> Data? {
            values[defaultName] as? Data
        }

        func set(_ value: Any?, forKey defaultName: String) {
            values[defaultName] = value
        }

        func removeObject(forKey defaultName: String) {
            values.removeValue(forKey: defaultName)
        }
    }

    func testLastWorkspaceReferencePersistsAndIsClaimedOnlyOncePerLaunch() throws {
        let reference = WorkspaceReference(
            id: UUID(),
            bookmarkData: Data("bookmark".utf8)
        )
        let encoded = try JSONEncoder().encode(reference)
        var state = WorkspaceLaunchState()

        XCTAssertEqual(state.takeReference(from: encoded), reference)
        XCTAssertNil(state.takeReference(from: encoded))
    }

    func testMissingOrInvalidReferenceIsIgnoredWithoutRetrying() {
        var missingState = WorkspaceLaunchState()
        var invalidState = WorkspaceLaunchState()

        XCTAssertNil(missingState.takeReference(from: nil))
        XCTAssertNil(missingState.takeReference(from: nil))
        XCTAssertNil(invalidState.takeReference(from: Data("invalid".utf8)))
        XCTAssertNil(invalidState.takeReference(from: nil))
    }

    func testRecentWorkspacesAreDeduplicatedPersistedAndClearable() {
        let storageKey = "last"
        let recentStorageKey = "recent"
        let defaults = MemoryStorage()
        let first = WorkspaceReference(id: UUID(), bookmarkData: Data("first".utf8))
        let second = WorkspaceReference(id: UUID(), bookmarkData: Data("second".utf8))
        let resolvedURLs = [
            first.id: URL(fileURLWithPath: "/tmp/first"),
            second.id: URL(fileURLWithPath: "/tmp/second"),
        ]
        let restoration = WorkspaceLaunchRestoration(
            defaults: defaults,
            storageKey: storageKey,
            recentStorageKey: recentStorageKey,
            resolveReferenceURL: { resolvedURLs[$0.id] }
        )

        restoration.remember(first)
        restoration.remember(second)
        restoration.remember(first)

        XCTAssertEqual(restoration.recentWorkspaces.map(\.id), [first.id, second.id])
        let restored = WorkspaceLaunchRestoration(
            defaults: defaults,
            storageKey: storageKey,
            recentStorageKey: recentStorageKey,
            resolveReferenceURL: { resolvedURLs[$0.id] }
        )
        XCTAssertEqual(restored.recentWorkspaces.map(\.id), [first.id, second.id])
        restored.clearRecentWorkspaces()
        XCTAssertTrue(restored.recentWorkspaces.isEmpty)
        XCTAssertNil(defaults.data(forKey: recentStorageKey))
    }
}

final class MarkdownEditTransformerTests: XCTestCase {
    func testInlineActionsWrapSelectionAndSelectEditableContent() {
        let bold = MarkdownEditTransformer.apply(
            .bold,
            to: "Make this bold",
            selection: NSRange(location: 10, length: 4)
        )
        XCTAssertEqual(bold.text, "Make this **bold**")
        XCTAssertEqual(bold.selection, NSRange(location: 12, length: 4))

        let link = MarkdownEditTransformer.apply(
            .link,
            to: "DiagramDown",
            selection: NSRange(location: 0, length: 11)
        )
        XCTAssertEqual(link.text, "[DiagramDown](https://)")
        XCTAssertEqual(
            (link.text as NSString).substring(with: link.selection),
            "https://"
        )
    }

    func testBlockActionsInsertListsAndTables() {
        let list = MarkdownEditTransformer.apply(
            .taskList,
            to: "first\nsecond",
            selection: NSRange(location: 0, length: 12)
        )
        XCTAssertEqual(list.text, "- [ ] first\n- [ ] second")

        let table = MarkdownEditTransformer.apply(
            .table,
            to: "",
            selection: NSRange(location: 0, length: 0)
        )
        XCTAssertTrue(table.text.contains("| Column 1 | Column 2 |"))
        XCTAssertTrue(table.text.contains("| --- | --- |"))
    }
}

final class MarkdownFileCodecTests: XCTestCase {
    func testUTF8RoundTripPreservesMarkdownAndUnicode() throws {
        let markdown = "# DiagramDown\n\n中文内容 🌏\n\n```mermaid\nA --> B\n```\n"
        let data = try MarkdownFileCodec.encode(markdown)

        XCTAssertEqual(try MarkdownFileCodec.decode(data), markdown)
    }

    func testInvalidUTF8IsRejected() {
        let invalidUTF8 = Data([0xC3, 0x28])

        XCTAssertThrowsError(try MarkdownFileCodec.decode(invalidUTF8)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadInapplicableStringEncoding)
        }
    }
}

final class OnboardingTests: XCTestCase {
    func testHelpLinksUseSecureProjectURLs() {
        let links = [
            DiagramDownLinks.project,
            DiagramDownLinks.feedback,
            DiagramDownLinks.releaseNotes,
        ]

        XCTAssertTrue(links.allSatisfy { $0.scheme == "https" })
        XCTAssertTrue(links.allSatisfy { $0.host == "github.com" })
        XCTAssertTrue(links.allSatisfy { $0.path.hasPrefix("/Weichen-LF/DiagramDown") })
    }

    func testBlankEditorGuidanceIsWorkspaceAppropriate() {
        XCTAssertEqual(EditorGuidance.placeholder, "Start writing Markdown.")
    }

    func testApplicationDoesNotAdvertiseSingleFileDocumentTypes() {
        XCTAssertNil(Bundle.main.infoDictionary?["CFBundleDocumentTypes"])
        XCTAssertNil(Bundle.main.infoDictionary?["UTImportedTypeDeclarations"])
        XCTAssertNil(Bundle.main.infoDictionary?["LSSupportsOpeningDocumentsInPlace"])
    }
}

final class DiagnosticsReportTests: XCTestCase {
    func testReportContainsActionableEnvironmentAndConfiguration() {
        let snapshot = DiagnosticsSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "0.19.0",
            buildNumber: "19",
            operatingSystem: "macOS test",
            architecture: "arm64",
            locale: "en_US",
            mermaidCLIAvailable: true,
            d2CLIAvailable: true,
            preferences: DiagnosticsPreferences(
                appearance: "dark",
                markdownTheme: "github",
                mermaidLightTheme: "forest",
                mermaidDarkTheme: "dark",
                previewZoom: 125,
                d2Layout: "elk",
                d2LightThemeID: 3,
                d2DarkThemeID: 201,
                d2Padding: 64,
                d2Sketch: true
            ),
            cache: D2CacheStatistics(fileCount: 4, totalBytes: 1_024)
        )

        let report = DiagnosticsReport.make(from: snapshot)

        XCTAssertTrue(report.contains("Version: 0.19.0 (19)"))
        XCTAssertTrue(report.contains("Architecture: arm64"))
        XCTAssertTrue(report.contains("Markdown theme: github"))
        XCTAssertTrue(report.contains("Layout: elk"))
        XCTAssertTrue(report.contains("Disk cache entries: 4"))
        XCTAssertTrue(report.contains("document content"))
    }

    func testCurrentReportDoesNotLeakUnknownPreferenceValuesOrCachePaths() throws {
        let suiteName = "DiagnosticsReportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let secret = "private-document-content-and-path"
        defaults.set(secret, forKey: PreviewPreferences.appearanceKey)
        defaults.set(secret, forKey: PreviewPreferences.markdownThemeKey)
        defaults.set(secret, forKey: PreviewPreferences.d2LayoutKey)

        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(secret, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: cacheURL) }

        let report = DiagnosticsReport.current(
            defaults: defaults,
            cacheDirectoryURL: cacheURL,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertFalse(report.contains(secret))
        XCTAssertTrue(report.contains("Appearance: system"))
        XCTAssertTrue(report.contains("Markdown theme: diagramDown"))
        XCTAssertTrue(report.contains("Layout: dagre"))
    }

    func testCacheStatisticsCountOnlyRegularSVGFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 12).write(
            to: directory.appendingPathComponent("first.svg")
        )
        try Data(repeating: 2, count: 20).write(
            to: directory.appendingPathComponent("second.SVG")
        )
        try Data(repeating: 3, count: 99).write(
            to: directory.appendingPathComponent("ignored.txt")
        )

        XCTAssertEqual(
            D2CacheStatistics.collect(at: directory),
            D2CacheStatistics(fileCount: 2, totalBytes: 32)
        )
    }
}

final class D2ConfigurationTests: XCTestCase {
    func testPreviewCacheDescriptorIsStable() {
        XCTAssertEqual(
            D2RenderConfiguration.preview.cacheDescriptor,
            "dagre\0" + "0\0" + "200\0" + "40\0" + "standard"
        )
    }

    func testEveryRenderingOptionChangesCacheIdentity() {
        let baseline = D2RenderConfiguration.preview
        let variants = [
            D2RenderConfiguration(
                layout: .elk,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: 3,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: 201,
                padding: baseline.padding,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: 64,
                sketch: baseline.sketch
            ),
            D2RenderConfiguration(
                layout: baseline.layout,
                lightThemeID: baseline.lightThemeID,
                darkThemeID: baseline.darkThemeID,
                padding: baseline.padding,
                sketch: true
            ),
        ]

        for variant in variants {
            XCTAssertNotEqual(variant.cacheDescriptor, baseline.cacheDescriptor)
        }
    }

    func testD2ErrorsHaveActionableMessages() {
        let errors: [D2RenderError] = [
            .executableMissing,
            .inputTooLarge,
            .timedOut,
            .cancelled,
            .processLaunchFailed("launch failed"),
            .processFailed(exitCode: 5, message: ""),
            .outputMissing,
            .outputTooLarge,
            .invalidSVG,
        ]

        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }
}

final class D2FormattingTests: XCTestCase {
    func testOnlyD2FencesUseTheOfficialFormatterCommand() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let formatterURL = directory.appendingPathComponent("d2")
        let formatter = """
        #!/bin/sh
        [ "$1" = "fmt" ] || exit 9
        printf 'formatted -> d2\n' > "$2"
        """
        try formatter.write(to: formatterURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: formatterURL.path
        )

        let service = D2RenderService(
            executableURL: formatterURL,
            cacheDirectoryURL: directory
        )
        let markdown = """
        ```D2
        a:     b
        ```

        ```mermaid
        graph TD
        A-->B
        ```
        """
        let result = try await service.formatFencedBlocks(in: markdown)

        XCTAssertTrue(result.contains("formatted -> d2"))
        XCTAssertTrue(result.contains("graph TD\nA-->B"))
    }

    func testMarkdownWithoutD2DoesNotRequireAFormatterExecutable() async throws {
        let service = D2RenderService(executableURL: URL(fileURLWithPath: "/missing"))
        let markdown = "```json\n{\"ok\":true}\n```"
        let result = try await service.formatFencedBlocks(in: markdown)
        XCTAssertEqual(result, markdown)
    }

    func testMissingD2FormatterLeavesD2FencesUnchanged() async throws {
        let service = D2RenderService(executableURL: URL(fileURLWithPath: "/missing"))
        let markdown = "```d2\na    ->    b\n```"
        let result = try await service.formatFencedBlocks(in: markdown)
        XCTAssertEqual(result, markdown)
    }
}

final class MarkdownFormattingServiceTests: XCTestCase {
    func testSwiftMarkdownFormatterCanonicalizesMarkupAndPreservesFencedCode() async throws {
        let source = """
        #  Heading

        - [x]  shipped

        | Name |State|
        |---|---|
        | Mark | ready |

        ~~done~~

        <kbd>raw</kbd>

        ```
        untouched    code
        ```

        ```json
        {"ok":true}
        ```

        ```mermaid
        flowchart LR
          A --> B
        ```
        """
        let formatted = try await MarkdownFormattingService.shared.format(
            source
        )

        XCTAssertTrue(formatted.contains("# Heading"))
        XCTAssertTrue(formatted.contains("- [x] shipped"))
        XCTAssertTrue(formatted.contains("Name"))
        XCTAssertTrue(formatted.contains("State"))
        XCTAssertTrue(formatted.contains("~done~"))
        XCTAssertTrue(formatted.contains("<kbd>raw</kbd>"))
        XCTAssertTrue(formatted.contains("untouched    code"))
        XCTAssertTrue(formatted.contains(#"{"ok":true}"#))
        XCTAssertTrue(formatted.contains("flowchart LR\n  A --> B"))
    }

    func testSwiftMarkdownFormattingIsIdempotent() async throws {
        let source = "#  Heading\n\n- first\n- second\n\n```json\n{\"ok\":true}\n```\n"
        let first = try await MarkdownFormattingService.shared.format(source)
        let second = try await MarkdownFormattingService.shared.format(first)
        XCTAssertEqual(second, first)
    }
}

final class DiagramToolRegistryTests: XCTestCase {
    func testInstallCommandsUseSupportedDistributionChannels() {
        XCTAssertEqual(
            DiagramToolKind.mermaid.installCommand,
            "npm install -g @mermaid-js/mermaid-cli"
        )
        XCTAssertEqual(DiagramToolKind.d2.installCommand, "brew install d2")
    }

    func testAutomaticSearchIgnoresRelativePATHEntries() {
        let directories = DiagramToolRegistry.defaultSearchDirectories(
            environment: ["PATH": "relative/bin:/absolute/bin"]
        )
        XCTAssertFalse(directories.map(\.path).contains { $0.hasSuffix("/relative/bin") })
        XCTAssertTrue(directories.map(\.path).contains("/absolute/bin"))
    }

    func testDiscoversHomebrewStyleExecutableAndReadsVersion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executable = directory.appendingPathComponent("mmdc")
        try "#!/bin/sh\nprintf '11.16.0\\n'\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let registry = DiagramToolRegistry(automaticDirectories: [directory])
        let status = await registry.status(for: .mermaid)
        guard case .installed(let tool) = status else {
            return XCTFail("Expected the fake Mermaid CLI to be discovered.")
        }
        XCTAssertEqual(tool.version, "11.16.0")
        XCTAssertEqual(tool.executableURL, executable.resolvingSymlinksInPath())
    }

    func testMissingToolReturnsResolutionError() async {
        let registry = DiagramToolRegistry(automaticDirectories: [])
        do {
            _ = try await registry.installedTool(for: .d2)
            XCTFail("Expected a missing-tool error.")
        } catch is DiagramToolResolutionError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class LocalDiagramCLIRenderTests: XCTestCase {
    func testD2UsesOnlyTheThemeForTheEffectiveAppearance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let captureURL = directory.appendingPathComponent("arguments.txt")
        let executable = directory.appendingPathComponent("d2")
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(captureURL.path)"
        for argument in "$@"; do output="$argument"; done
        printf '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60"></svg>' > "$output"
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        let service = D2RenderService(executableURL: executable)
        _ = try await service.render(
            source: "a -> b",
            configuration: .preview,
            appearance: "dark"
        )

        let arguments = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertTrue(arguments.contains("--theme\n200\n"))
        XCTAssertFalse(arguments.contains("--dark-theme"))
    }

    func testExternalRunnerTimesOut() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("slow")
        try "#!/bin/sh\nsleep 5\n".write(
            to: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable.path
        )

        do {
            _ = try await ExternalProcessRunner().run(
                executableURL: executable,
                arguments: [],
                timeout: .milliseconds(50)
            )
            XCTFail("Expected the command to time out.")
        } catch ExternalProcessRunnerError.timedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class ScrollSyncStateTests: XCTestCase {
    func testInitialPositionIsAtDocumentStart() {
        XCTAssertEqual(ScrollSyncPosition.initial.sourceLine, 1)
        XCTAssertEqual(ScrollSyncPosition.initial.progress, 0)
        XCTAssertEqual(ScrollSyncPosition.initial.generation, 0)
    }

    func testInitialTargetDoesNotAnimateOrUseFallback() {
        XCTAssertEqual(ScrollSyncTarget.initial.sourceLine, 1)
        XCTAssertEqual(ScrollSyncTarget.initial.progress, 0)
        XCTAssertFalse(ScrollSyncTarget.initial.usesProgressFallback)
        XCTAssertFalse(ScrollSyncTarget.initial.animated)
        XCTAssertEqual(ScrollSyncTarget.initial.generation, 0)
    }
}
