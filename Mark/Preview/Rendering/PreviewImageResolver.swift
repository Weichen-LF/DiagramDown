//
//  PreviewImageResolver.swift
//  DiagramDown
//

import Foundation

nonisolated enum PreviewImageLoadingError: Equatable, LocalizedError, Sendable {
    case invalidEmbeddedImage
    case remoteImageDisabled
    case unsupportedFormat
    case missingOrTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidEmbeddedImage:
            "The embedded image is invalid or too large."
        case .remoteImageDisabled:
            "Remote images are disabled."
        case .unsupportedFormat:
            "The local image format is unsupported."
        case .missingOrTooLarge:
            "The image is missing or too large."
        }
    }
}

nonisolated enum PreviewImageResolver {
    private static let supportedFileExtensions: Set<String> = [
        "png",
        "jpg",
        "jpeg",
        "gif",
        "tif",
        "tiff",
        "bmp",
        "heic",
        "heif",
        "webp",
        "svg",
        "ico",
    ]

    static func data(
        for image: PreviewImage,
        documentURL: URL?,
        workspaceRootURL _: URL
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

        let candidate: URL
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsedURL = URL(string: trimmedSource), parsedURL.scheme != nil {
            guard parsedURL.isFileURL else {
                throw PreviewImageLoadingError.remoteImageDisabled
            }
            candidate = parsedURL
        } else {
            let decodedSource = trimmedSource.removingPercentEncoding ?? trimmedSource
            if decodedSource.hasPrefix("~/") {
                candidate = URL(
                    fileURLWithPath: NSString(string: decodedSource).expandingTildeInPath
                )
            } else if NSString(string: decodedSource).isAbsolutePath {
                candidate = URL(fileURLWithPath: decodedSource)
            } else {
                guard let documentDirectory = documentURL?.deletingLastPathComponent() else {
                    throw PreviewImageLoadingError.missingOrTooLarge
                }
                candidate = documentDirectory.appendingPathComponent(decodedSource)
            }
        }

        let resolvedCandidate = candidate
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard supportedFileExtensions.contains(
            resolvedCandidate.pathExtension.lowercased()
        ) else {
            throw PreviewImageLoadingError.unsupportedFormat
        }

        do {
            let values = try resolvedCandidate.resourceValues(forKeys: [
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
            let data = try Data(contentsOf: resolvedCandidate, options: [.mappedIfSafe])
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
