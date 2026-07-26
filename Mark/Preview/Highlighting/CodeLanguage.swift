//
//  CodeLanguage.swift
//  DiagramDown
//

import Foundation

nonisolated enum CodeLanguage: String, CaseIterable, Hashable, Sendable {
    case bash
    case c
    case cpp
    case css
    case diff
    case dockerfile
    case go
    case html
    case java
    case javascript
    case jsx
    case json
    case lua
    case python
    case rust
    case sql
    case swift
    case typescript
    case tsx
    case yaml
    case mermaid
    case d2

    static func resolve(_ rawValue: String?) -> CodeLanguage? {
        guard let rawValue else {
            return nil
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .first?
            .lowercased()

        return switch normalized {
        case "bash", "sh", "shell", "zsh": .bash
        case "c": .c
        case "cpp", "c++", "cc", "cxx": .cpp
        case "css": .css
        case "diff", "patch": .diff
        case "dockerfile", "docker": .dockerfile
        case "go", "golang": .go
        case "html", "htm": .html
        case "java": .java
        case "javascript", "js": .javascript
        case "jsx": .jsx
        case "json", "jsonc": .json
        case "lua": .lua
        case "python", "py": .python
        case "rust", "rs": .rust
        case "sql": .sql
        case "swift": .swift
        case "typescript", "ts": .typescript
        case "tsx": .tsx
        case "yaml", "yml": .yaml
        case "mermaid": .mermaid
        case "d2": .d2
        default: nil
        }
    }
}
