//
//  TreeSitterLanguageRegistry.swift
//  DiagramDown
//

import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterJavaScript
import TreeSitterJSON
import TreeSitterLua
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import TreeSitterYAML

struct TreeSitterLanguageDefinition: Sendable {
    let language: CodeLanguage
    let grammarVersion: String
    let configuration: LanguageConfiguration
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
        let configuration: LanguageConfiguration
        if let bundleName {
            configuration = try LanguageConfiguration(
                treeSitterLanguage,
                name: name,
                bundleName: bundleName
            )
        } else {
            configuration = try LanguageConfiguration(
                treeSitterLanguage,
                name: name
            )
        }

        return TreeSitterLanguageDefinition(
            language: language,
            grammarVersion: version,
            configuration: configuration
        )
    }
}
