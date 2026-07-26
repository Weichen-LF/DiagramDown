//
//  PreviewImageResolver.swift
//  DiagramDown
//

import Foundation

nonisolated enum PreviewImageLoadingError: Equatable, LocalizedError, Sendable {
    case invalidEmbeddedImage
    case remoteImageDisabled
    case outsideWorkspace
    case missingOrTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidEmbeddedImage:
            "The embedded image is invalid or too large."
        case .remoteImageDisabled:
            "Remote images are disabled."
        case .outsideWorkspace:
            "The image is outside this workspace."
        case .missingOrTooLarge:
            "The image is missing, unsupported, or too large."
        }
    }
}

nonisolated enum PreviewImageResolver {
    static func data(
        for image: PreviewImage,
        documentURL: URL?,
        workspaceRootURL: URL
    ) throws -> Data {
        let source = image.source
        if source.lowercased().hasPrefix("data:image/") {
            guard let comma = source.firstIndex(of: ","),
                  source[..<comma].lowercased().contains(";base64"),
                  let data = Data(
                    base64Encoded: String(source[source.index(after: comma)...])
                  ),
                  data.count <= 8 * 1_024 * 1_024 else {
                throw PreviewImageLoadingError.invalidEmbeddedImage
            }
            return data
        }

        guard !source.contains("://"),
              let documentDirectory = documentURL?.deletingLastPathComponent() else {
            throw PreviewImageLoadingError.remoteImageDisabled
        }

        let candidate = documentDirectory
            .appendingPathComponent(source)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let canonicalRoot = workspaceRootURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard WorkspacePathPolicy.contains(candidate, within: canonicalRoot) else {
            throw PreviewImageLoadingError.outsideWorkspace
        }

        do {
            let values = try candidate.resourceValues(forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size <= 16 * 1_024 * 1_024 else {
                throw PreviewImageLoadingError.missingOrTooLarge
            }
            let data = try Data(contentsOf: candidate, options: [.mappedIfSafe])
            guard data.count <= 16 * 1_024 * 1_024 else {
                throw PreviewImageLoadingError.missingOrTooLarge
            }
            return data
        } catch let error as PreviewImageLoadingError {
            throw error
        } catch {
            throw PreviewImageLoadingError.missingOrTooLarge
        }
    }
}
