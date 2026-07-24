//
//  WorkspaceView.swift
//  DiagramDown
//

import SwiftUI

struct WorkspaceWindowView: View {
    let reference: WorkspaceReference
    @State private var session: WorkspaceSession?
    @State private var loadingError: String?

    var body: some View {
        Group {
            if let session {
                WorkspaceContentView(session: session)
            } else if let loadingError {
                ContentUnavailableView(
                    "Unable to Open Folder",
                    systemImage: "folder.badge.questionmark",
                    description: Text(loadingError)
                )
            } else {
                ProgressView("Opening folder…")
            }
        }
        .task(id: reference.id) {
            guard session == nil else {
                return
            }
            do {
                session = try WorkspaceSession(reference: reference)
            } catch {
                loadingError = error.localizedDescription
            }
        }
    }
}

private struct WorkspaceContentView: View {
    @ObservedObject var session: WorkspaceSession
    @State private var pendingCloseFileID: OpenFileBuffer.ID?

    var body: some View {
        HSplitView {
            if session.sidebarVisible {
                sidebar
                    .frame(minWidth: 190, idealWidth: 260, maxWidth: 420)
            }

            workspaceDetail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 460)
        .navigationTitle(session.rootURL.lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    session.sidebarVisible.toggle()
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }
        }
        .focusedSceneValue(
            \.workspaceSaveAction,
            session.activeFile == nil
                ? nil
                : WorkspaceSaveAction {
                    Task {
                        await session.saveActiveFile()
                    }
                }
        )
        .task {
            await session.loadRoot()
        }
        .alert(
            "Workspace Error",
            isPresented: Binding(
                get: { session.fileErrorDescription != nil },
                set: { isPresented in
                    if !isPresented {
                        session.clearFileError()
                    }
                }
            )
        ) {
            Button("OK") {
                session.clearFileError()
            }
        } message: {
            Text(session.fileErrorDescription ?? "")
        }
        .confirmationDialog(
            "Do you want to save the changes?",
            isPresented: Binding(
                get: { pendingCloseFileID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCloseFileID = nil
                    }
                }
            )
        ) {
            Button("Save") {
                saveAndClosePendingFile()
            }
            Button("Discard Changes", role: .destructive) {
                discardAndClosePendingFile()
            }
            Button("Cancel", role: .cancel) {
                pendingCloseFileID = nil
            }
        } message: {
            Text("Your changes will be lost if you don’t save them.")
        }
    }

    private var workspaceDetail: some View {
        VStack(spacing: 0) {
            if !session.openFiles.isEmpty {
                WorkspaceTabBar(
                    files: session.openFiles,
                    activeFileID: session.activeFileID,
                    activate: session.activateFile,
                    close: requestClose
                )
                Divider()
            }

            if let activeFile = session.activeFile {
                WorkspaceEditorContainer(buffer: activeFile)
            } else {
                ContentUnavailableView(
                    "No File Open",
                    systemImage: "doc.text",
                    description: Text("Select a Markdown file from the sidebar.")
                )
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(session.rootURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if session.rootNodes.isEmpty, session.loadingDirectoryIDs.contains("") {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = session.treeErrorDescription {
                ContentUnavailableView(
                    "Unable to Read Folder",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                List(session.visibleTreeRows) { row in
                    WorkspaceTreeRowView(
                        row: row,
                        isExpanded: session.expandedDirectoryIDs.contains(row.node.id),
                        isLoading: session.loadingDirectoryIDs.contains(row.node.id)
                            || session.openingFileIDs.contains(row.node.id),
                        isActive: session.activeFile?.url
                            == session.rootURL
                                .appendingPathComponent(row.node.relativePath)
                                .standardizedFileURL
                    ) {
                        handleTreeRow(row.node)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func handleTreeRow(_ node: FileTreeNode) {
        Task {
            if node.isDirectory {
                await session.toggleDirectory(node)
            } else {
                await session.openFile(node)
            }
        }
    }

    private func requestClose(_ id: OpenFileBuffer.ID) {
        if session.closeDecision(for: id) == .needsConfirmation {
            pendingCloseFileID = id
        } else {
            session.closeFile(id: id)
        }
    }

    private func saveAndClosePendingFile() {
        guard let id = pendingCloseFileID else {
            return
        }
        pendingCloseFileID = nil
        Task {
            if await session.saveFile(id: id) {
                session.closeFile(id: id)
            }
        }
    }

    private func discardAndClosePendingFile() {
        guard let id = pendingCloseFileID else {
            return
        }
        pendingCloseFileID = nil
        session.closeFile(id: id, discardingChanges: true)
    }
}

private struct WorkspaceEditorContainer: View {
    @ObservedObject var buffer: OpenFileBuffer

    var body: some View {
        EditorPreviewSurface(
            text: $buffer.text,
            fileURL: buffer.url,
            storedViewMode: $buffer.storedViewMode,
            session: buffer.editorPreviewSession
        )
        .id(buffer.id)
    }
}

private struct WorkspaceTabBar: View {
    let files: [OpenFileBuffer]
    let activeFileID: OpenFileBuffer.ID?
    let activate: (OpenFileBuffer.ID) -> Void
    let close: (OpenFileBuffer.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(files) { file in
                    WorkspaceTab(
                        file: file,
                        isActive: file.id == activeFileID,
                        activate: { activate(file.id) },
                        close: { close(file.id) }
                    )
                }
            }
        }
        .frame(height: 34)
        .background(.bar)
    }
}

private struct WorkspaceTab: View {
    @ObservedObject var file: OpenFileBuffer
    let isActive: Bool
    let activate: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: activate) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.richtext")
                    Text(file.url.lastPathComponent)
                        .lineLimit(1)
                    if file.isDirty {
                        Circle()
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Unsaved changes")
                    }
                }
            }
            .buttonStyle(.plain)

            if file.isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Close \(file.url.lastPathComponent)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isActive ? Color.accentColor.opacity(0.16) : Color.clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .contain)
    }
}

private struct WorkspaceTreeRowView: View {
    let row: WorkspaceTreeRow
    let isExpanded: Bool
    let isLoading: Bool
    let isActive: Bool
    let activate: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 14, height: 1)

            if row.node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12, height: 1)
            }

            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            Text(row.node.name)
                .lineLimit(1)
                .foregroundStyle(row.node.canOpen || row.node.isDirectory ? .primary : .secondary)

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if row.node.isDirectory || row.node.canOpen {
                activate()
            }
        }
        .listRowBackground(isActive ? Color.accentColor.opacity(0.14) : Color.clear)
        .help(row.node.relativePath)
    }

    private var iconName: String {
        switch row.node.kind {
        case .directory:
            isExpanded ? "folder.fill.badge.minus" : "folder"
        case .markdownFile:
            "doc.richtext"
        case .otherFile:
            "doc"
        }
    }

    private var iconColor: Color {
        row.node.kind == .directory ? .accentColor : .secondary
    }
}
