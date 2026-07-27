//
//  DiagnosticsReport.swift
//  DiagramDown
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct D2CacheStatistics: Equatable, Sendable {
    let fileCount: Int
    let totalBytes: Int64

    static let empty = D2CacheStatistics(fileCount: 0, totalBytes: 0)

    static func collect(
        at directoryURL: URL?,
        fileManager: FileManager = .default
    ) -> D2CacheStatistics {
        guard let directoryURL,
              let enumerator = fileManager.enumerator(
                  at: directoryURL,
                  includingPropertiesForKeys: [
                      .fileSizeKey,
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ],
                  options: [.skipsHiddenFiles]
              ) else {
            return .empty
        }

        var fileCount = 0
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "svg",
                  let values = try? fileURL.resourceValues(forKeys: [
                      .fileSizeKey,
                      .isRegularFileKey,
                      .isSymbolicLinkKey,
                  ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                continue
            }
            fileCount += 1
            totalBytes += Int64(values.fileSize ?? 0)
        }
        return D2CacheStatistics(fileCount: fileCount, totalBytes: totalBytes)
    }
}

struct DiagnosticsPreferences: Equatable, Sendable {
    let appearance: String
    let markdownTheme: String
    let mermaidRenderer: String
    let mermaidLightTheme: String
    let mermaidDarkTheme: String
    let previewZoom: Int
    let d2Layout: String
    let d2LightThemeID: Int
    let d2DarkThemeID: Int
    let d2Padding: Int
    let d2Sketch: Bool

    static func current(from defaults: UserDefaults = .standard) -> DiagnosticsPreferences {
        let d2Defaults = D2RenderConfiguration.preview
        return DiagnosticsPreferences(
            appearance: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.appearanceKey),
                as: AppAppearance.self,
                fallback: .system
            ),
            markdownTheme: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.markdownThemeKey),
                as: MarkdownPreviewTheme.self,
                fallback: .diagramDown
            ),
            mermaidRenderer: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.mermaidRendererKey),
                as: MermaidRendererEngine.self,
                fallback: .mmdr
            ),
            mermaidLightTheme: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.mermaidLightThemeKey),
                as: MermaidPreviewTheme.self,
                fallback: .default
            ),
            mermaidDarkTheme: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.mermaidDarkThemeKey),
                as: MermaidPreviewTheme.self,
                fallback: .dark
            ),
            previewZoom: PreviewZoom.clamped(
                integer(
                    from: defaults,
                    key: PreviewPreferences.zoomKey,
                    fallback: PreviewZoom.defaultValue
                )
            ),
            d2Layout: validatedRawValue(
                defaults.string(forKey: PreviewPreferences.d2LayoutKey),
                as: D2RenderConfiguration.Layout.self,
                fallback: .dagre
            ),
            d2LightThemeID: integer(
                from: defaults,
                key: PreviewPreferences.d2LightThemeIDKey,
                fallback: d2Defaults.lightThemeID
            ),
            d2DarkThemeID: integer(
                from: defaults,
                key: PreviewPreferences.d2DarkThemeIDKey,
                fallback: d2Defaults.darkThemeID
            ),
            d2Padding: min(
                max(integer(
                    from: defaults,
                    key: PreviewPreferences.d2PaddingKey,
                    fallback: d2Defaults.padding
                ), 0),
                200
            ),
            d2Sketch: boolean(
                from: defaults,
                key: PreviewPreferences.d2SketchKey,
                fallback: d2Defaults.sketch
            )
        )
    }

    private static func validatedRawValue<Value: RawRepresentable>(
        _ value: String?,
        as type: Value.Type,
        fallback: Value
    ) -> String where Value.RawValue == String {
        Value(rawValue: value ?? "")?.rawValue ?? fallback.rawValue
    }

    private static func integer(
        from defaults: UserDefaults,
        key: String,
        fallback: Int
    ) -> Int {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        return defaults.integer(forKey: key)
    }

    private static func boolean(
        from defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return fallback
        }
        return defaults.bool(forKey: key)
    }
}

struct DiagnosticsSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let appVersion: String
    let buildNumber: String
    let operatingSystem: String
    let architecture: String
    let locale: String
    let mermaidCLIAvailable: Bool
    let mmdrCLIAvailable: Bool
    let d2CLIAvailable: Bool
    let preferences: DiagnosticsPreferences
    let cache: D2CacheStatistics
}

enum DiagnosticsReport {
    static func current(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        cacheDirectoryURL: URL? = nil,
        generatedAt: Date = Date()
    ) -> String {
        let cacheURL = cacheDirectoryURL ?? defaultCacheDirectoryURL(
            bundle: bundle,
            fileManager: fileManager
        )
        let snapshot = DiagnosticsSnapshot(
            generatedAt: generatedAt,
            appVersion: bundle.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: bundle.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            locale: Locale.current.identifier,
            mermaidCLIAvailable: toolAvailable(
                .mermaid,
                defaults: defaults,
                fileManager: fileManager
            ),
            mmdrCLIAvailable: toolAvailable(
                .mmdr,
                defaults: defaults,
                fileManager: fileManager
            ),
            d2CLIAvailable: toolAvailable(
                .d2,
                defaults: defaults,
                fileManager: fileManager
            ),
            preferences: DiagnosticsPreferences.current(from: defaults),
            cache: D2CacheStatistics.collect(at: cacheURL, fileManager: fileManager)
        )
        return make(from: snapshot)
    }

    static func make(from snapshot: DiagnosticsSnapshot) -> String {
        let date = ISO8601DateFormatter().string(from: snapshot.generatedAt)
        return """
        DiagramDown Diagnostics
        Generated: \(date)

        Application
        Version: \(snapshot.appVersion) (\(snapshot.buildNumber))
        macOS: \(snapshot.operatingSystem)
        Architecture: \(snapshot.architecture)
        Locale: \(snapshot.locale)

        Preview Preferences
        Appearance: \(snapshot.preferences.appearance)
        Markdown theme: \(snapshot.preferences.markdownTheme)
        Mermaid renderer: \(snapshot.preferences.mermaidRenderer)
        Mermaid light theme: \(snapshot.preferences.mermaidLightTheme)
        Mermaid dark theme: \(snapshot.preferences.mermaidDarkTheme)
        Preview zoom: \(snapshot.preferences.previewZoom)%

        Diagram Tools
        Mermaid CLI available: \(yesNo(snapshot.mermaidCLIAvailable))
        mmdr available: \(yesNo(snapshot.mmdrCLIAvailable))
        D2 CLI available: \(yesNo(snapshot.d2CLIAvailable))

        D2 Preview
        Layout: \(snapshot.preferences.d2Layout)
        Light theme ID: \(snapshot.preferences.d2LightThemeID)
        Dark theme ID: \(snapshot.preferences.d2DarkThemeID)
        Padding: \(snapshot.preferences.d2Padding)
        Sketch: \(yesNo(snapshot.preferences.d2Sketch))
        Disk cache entries: \(snapshot.cache.fileCount)
        Disk cache bytes: \(snapshot.cache.totalBytes)

        Privacy
        This report excludes document content, document names, file paths, cache filenames, and personal identifiers.
        """
    }

    private static func defaultCacheDirectoryURL(
        bundle: Bundle,
        fileManager: FileManager
    ) -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(
                bundle.bundleIdentifier ?? "me.walt.diagramdown",
                isDirectory: true
            )
            .appendingPathComponent("d2", isDirectory: true)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }

    private static func toolAvailable(
        _ kind: DiagramToolKind,
        defaults: UserDefaults,
        fileManager: FileManager
    ) -> Bool {
        if let customPath = defaults.string(forKey: kind.customPathPreferenceKey),
           !customPath.isEmpty {
            return fileManager.isExecutableFile(atPath: customPath)
        }
        return DiagramToolRegistry.defaultSearchDirectories(
            environment: ProcessInfo.processInfo.environment
        ).contains { directory in
            fileManager.isExecutableFile(
                atPath: directory.appendingPathComponent(kind.executableName).path
            )
        }
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }
}

@MainActor
enum DiagnosticsExporter {
    static func export() {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.nameFieldStringValue = "DiagramDown-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            let report = DiagnosticsReport.current()
            try Data(report.utf8).write(to: destination, options: .atomic)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "The diagnostics report could not be exported."
            alert.runModal()
        }
    }
}
