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

    var body: some View {
        HSplitView {
            if session.sidebarVisible {
                sidebar
                    .frame(minWidth: 190, idealWidth: 260, maxWidth: 420)
            }

            ContentUnavailableView(
                "No File Open",
                systemImage: "doc.text",
                description: Text("Select a Markdown file from the sidebar.")
            )
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
        .task {
            await session.loadRoot()
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
                    ) {
                        Task {
                            await session.toggleDirectory(row.node)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct WorkspaceTreeRowView: View {
    let row: WorkspaceTreeRow
    let isExpanded: Bool
    let isLoading: Bool
    let toggleDirectory: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 14, height: 1)

            if row.node.isDirectory {
                Button(action: toggleDirectory) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
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
            if row.node.isDirectory {
                toggleDirectory()
            }
        }
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
