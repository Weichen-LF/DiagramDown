//
//  TreeSitterLanguageRegistry.swift
//  DiagramDown
//

import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterDockerfile
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterLua
import TreeSitterPython
import TreeSitterSqlBigquery
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

nonisolated struct TreeSitterLanguageDefinition: Sendable {
    let language: CodeLanguage
    let grammarVersion: String
    let configuration: LanguageConfiguration
}

nonisolated enum TreeSitterLanguageRegistryError: LocalizedError, Sendable {
    case queryBundleMissing(String)

    var errorDescription: String? {
        switch self {
        case .queryBundleMissing(let bundleName):
            "The bundled Tree-sitter queries are missing for \(bundleName)."
        }
    }
}

nonisolated struct TreeSitterLanguageRegistry {
    func definition(for language: CodeLanguage) throws -> TreeSitterLanguageDefinition? {
        switch language {
        case .bash:
            try definition(
                language: .bash,
                version: "0.25.1",
                pointer: tree_sitter_bash(),
                name: "Bash"
            )
        case .dockerfile:
            try definition(
                language: .dockerfile,
                version: "0.2.0",
                pointer: tree_sitter_dockerfile(),
                name: "Dockerfile"
            )
        case .go:
            try definition(
                language: .go,
                version: "0.25.0",
                pointer: tree_sitter_go(),
                name: "Go"
            )
        case .javascript, .jsx:
            try definition(
                language: language,
                version: "0.23.1",
                pointer: tree_sitter_javascript(),
                name: "JavaScript"
            )
        case .json:
            try definition(
                language: .json,
                version: "0.24.8",
                pointer: tree_sitter_json(),
                name: "JSON"
            )
        case .lua:
            try definition(
                language: .lua,
                version: "0.3.0",
                pointer: tree_sitter_lua(),
                name: "Lua"
            )
        case .python:
            try definition(
                language: .python,
                version: "0.23.6",
                pointer: tree_sitter_python(),
                name: "Python"
            )
        case .sql:
            try definition(
                language: .sql,
                version: "0.8.0",
                pointer: tree_sitter_sql_bigquery(),
                name: "SqlBigquery"
            )
        case .swift:
            try definition(
                language: .swift,
                version: "0.7.3",
                pointer: tree_sitter_swift(),
                name: "Swift"
            )
        case .typescript:
            try definition(
                language: .typescript,
                version: "0.23.2",
                pointer: tree_sitter_typescript(),
                name: "TypeScript"
            )
        case .tsx:
            try definition(
                language: .tsx,
                version: "0.23.2",
                pointer: tree_sitter_tsx(),
                name: "TSX",
                bundleName: "TreeSitterTypeScript_TreeSitterTSX"
            )
        case .yaml:
            try definition(
                language: .yaml,
                version: "0.7.0",
                pointer: tree_sitter_yaml(),
                name: "YAML"
            )
        default:
            nil
        }
    }

    private func definition(
        language: CodeLanguage,
        version: String,
        pointer: OpaquePointer,
        name: String,
        bundleName: String? = nil
    ) throws -> TreeSitterLanguageDefinition {
        let treeSitterLanguage = Language(pointer)
        let resolvedBundleName =
            bundleName ?? "TreeSitter\(name)_TreeSitter\(name)"
        let configuration = try LanguageConfiguration(
            treeSitterLanguage,
            name: name,
            queriesURL: try queriesURL(for: resolvedBundleName)
        )

        return TreeSitterLanguageDefinition(
            language: language,
            grammarVersion: version,
            configuration: configuration
        )
    }

    private func queriesURL(for bundleName: String) throws -> URL {
        let bundleFileName = "\(bundleName).bundle"
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        var resourceRoots: [URL] = []

        for bundle in bundles {
            if let resourceURL = bundle.resourceURL {
                resourceRoots.append(resourceURL)
            }
            resourceRoots.append(bundle.bundleURL.deletingLastPathComponent())
        }

        for root in resourceRoots {
            let candidate = root
                .appendingPathComponent(bundleFileName, isDirectory: true)
                .appendingPathComponent("Contents/Resources/queries", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            ),
               isDirectory.boolValue,
               FileManager.default.isReadableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw TreeSitterLanguageRegistryError.queryBundleMissing(bundleName)
    }
}
