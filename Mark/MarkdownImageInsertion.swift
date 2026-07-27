//
//  MarkdownImageInsertion.swift
//  DiagramDown
//

import AppKit
import Foundation
import UniformTypeIdentifiers

nonisolated enum MarkdownImageInsertionError: LocalizedError, Equatable, Sendable {
    case documentNotSaved
    case cancelled
    case copyFailed(String)
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .documentNotSaved:
            "Save the Markdown file before inserting an image with a relative path."
        case .cancelled:
            "Image insertion was cancelled."
        case .copyFailed(let message):
            message
        case .unsupportedImage:
            "The selected file is not a supported image format."
        }
    }
}

nonisolated enum MarkdownImageInsertion {
    static let assetsDirectoryName = "assets"

    static let allowedContentTypes: [UTType] = [
        .png,
        .jpeg,
        .gif,
        .tiff,
        .bmp,
        .webP,
        .heic,
        .heif,
        .svg,
    ] + [
        UTType(filenameExtension: "ico"),
    ].compactMap { $0 }

    static func markdown(
        alt: String,
        path: String
    ) -> String {
        "![\(alt)](\(path))"
    }

    static func altText(fromFileName fileName: String) -> String {
        fileName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    static func insert(
        alt: String,
        path: String,
        into source: String,
        selection: NSRange
    ) -> MarkdownEditResult {
        MarkdownEditTransformer.insertImage(
            markdown(alt: alt, path: path),
            source: source,
            selection: selection
        )
    }

    static func relativeMarkdownPath(
        from documentDirectory: URL,
        to fileURL: URL
    ) -> String {
        let from = documentDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let to = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let fromComponents = from.pathComponents
        let toComponents = to.pathComponents

        var common = 0
        while common < fromComponents.count,
              common < toComponents.count,
              fromComponents[common] == toComponents[common] {
            common += 1
        }

        let ups = Array(repeating: "..", count: fromComponents.count - common)
        let downs = Array(toComponents.dropFirst(common))
        let parts = ups + downs
        guard !parts.isEmpty else {
            return encodePathComponent(to.lastPathComponent)
        }
        return parts.map { component in
            if component == ".." || component == "." {
                return component
            }
            return encodePathComponent(component)
        }.joined(separator: "/")
    }

    static func uniqueDestinationURL(
        in directory: URL,
        preferredFileName: String
    ) -> URL {
        let baseName = URL(fileURLWithPath: preferredFileName).deletingPathExtension()
            .lastPathComponent
        let ext = URL(fileURLWithPath: preferredFileName).pathExtension
        let fileManager = FileManager.default
        var candidate = directory.appendingPathComponent(preferredFileName)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty
                ? "\(baseName)-\(index)"
                : "\(baseName)-\(index).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            index += 1
        }
        return candidate
    }

    static func copyIntoAssets(
        sourceURL: URL,
        workspaceRootURL: URL
    ) throws -> URL {
        let assetsURL = workspaceRootURL.appendingPathComponent(
            assetsDirectoryName,
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(
                at: assetsURL,
                withIntermediateDirectories: true
            )
            let destination = uniqueDestinationURL(
                in: assetsURL,
                preferredFileName: sourceURL.lastPathComponent
            )
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination.standardizedFileURL
        } catch {
            throw MarkdownImageInsertionError.copyFailed(
                error.localizedDescription
            )
        }
    }

    static func resolvedImageURL(
        selectedURL: URL,
        copyToAssets: Bool,
        workspaceRootURL: URL
    ) throws -> URL {
        let extensionName = selectedURL.pathExtension.lowercased()
        guard PreviewImageResolver.supportedExtensions.contains(extensionName) else {
            throw MarkdownImageInsertionError.unsupportedImage
        }
        if copyToAssets {
            return try copyIntoAssets(
                sourceURL: selectedURL,
                workspaceRootURL: workspaceRootURL
            )
        }
        return selectedURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func markdownPath(
        for imageURL: URL,
        documentURL: URL
    ) -> String {
        let documentDirectory = documentURL.deletingLastPathComponent()
        return relativeMarkdownPath(from: documentDirectory, to: imageURL)
    }

    private static func encodePathComponent(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // Parentheses are urlPathAllowed but terminate Markdown inline links.
        allowed.remove(charactersIn: "/()")
        return component.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? component
    }
}

@MainActor
enum MarkdownImagePicker {
    static func choose(
        documentURL: URL?,
        workspaceRootURL: URL
    ) async -> Result<(alt: String, path: String), MarkdownImageInsertionError> {
        guard let documentURL else {
            return .failure(.documentNotSaved)
        }

        let panel = NSOpenPanel()
        panel.title = "Insert Image"
        panel.prompt = "Insert"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MarkdownImageInsertion.allowedContentTypes

        let checkbox = NSButton(
            checkboxWithTitle: "Copy to workspace assets/",
            target: nil,
            action: nil
        )
        checkbox.state = .on
        panel.accessoryView = checkbox

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }

        guard response == .OK, let selectedURL = panel.url else {
            return .failure(.cancelled)
        }

        let copyToAssets = checkbox.state == .on
        do {
            let imageURL = try await Task.detached(priority: .userInitiated) {
                try MarkdownImageInsertion.resolvedImageURL(
                    selectedURL: selectedURL,
                    copyToAssets: copyToAssets,
                    workspaceRootURL: workspaceRootURL
                )
            }.value
            let alt = MarkdownImageInsertion.altText(
                fromFileName: imageURL.deletingPathExtension().lastPathComponent
            )
            let path = MarkdownImageInsertion.markdownPath(
                for: imageURL,
                documentURL: documentURL
            )
            return .success((alt: alt, path: path))
        } catch let error as MarkdownImageInsertionError {
            return .failure(error)
        } catch {
            return .failure(.copyFailed(error.localizedDescription))
        }
    }
}
