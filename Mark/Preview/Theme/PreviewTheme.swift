//
//  PreviewTheme.swift
//  DiagramDown
//

import SwiftUI

struct PreviewTheme {
    let id: String
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let subtleBackground: Color
    let border: Color
    let blockQuoteBorder: Color
    let codeTheme: CodeTheme

    static func resolved(
        configuration: PreviewConfiguration,
        colorScheme: ColorScheme
    ) -> PreviewTheme {
        let effectiveScheme: ColorScheme = switch configuration.appearance {
        case .system:
            colorScheme
        case .light:
            .light
        case .dark:
            .dark
        }
        let dark = effectiveScheme == .dark
        let codeTheme = CodeTheme.resolved(
            markdownTheme: configuration.markdownTheme,
            appearance: effectiveScheme
        )

        return switch (configuration.markdownTheme, dark) {
        case (.github, false):
            PreviewTheme(
                id: "github-light",
                background: Color(hex: 0xffffff),
                primaryText: Color(hex: 0x24292f),
                secondaryText: Color(hex: 0x57606a),
                accent: Color(hex: 0x0969da),
                subtleBackground: Color(hex: 0xf6f8fa),
                border: Color(hex: 0xd0d7de),
                blockQuoteBorder: Color(hex: 0xd0d7de),
                codeTheme: codeTheme
            )
        case (.github, true):
            PreviewTheme(
                id: "github-dark",
                background: Color(hex: 0x0d1117),
                primaryText: Color(hex: 0xc9d1d9),
                secondaryText: Color(hex: 0x8b949e),
                accent: Color(hex: 0x58a6ff),
                subtleBackground: Color(hex: 0x161b22),
                border: Color(hex: 0x30363d),
                blockQuoteBorder: Color(hex: 0x3b434b),
                codeTheme: codeTheme
            )
        case (.paper, false):
            PreviewTheme(
                id: "paper-light",
                background: Color(hex: 0xfbf7ed),
                primaryText: Color(hex: 0x302c27),
                secondaryText: Color(hex: 0x746d64),
                accent: Color(hex: 0x8f3b32),
                subtleBackground: Color(hex: 0xf4efe4),
                border: Color(hex: 0xd8d0c3),
                blockQuoteBorder: Color(hex: 0xbba98f),
                codeTheme: codeTheme
            )
        case (.paper, true):
            PreviewTheme(
                id: "paper-dark",
                background: Color(hex: 0x1d1a17),
                primaryText: Color(hex: 0xe6dfd2),
                secondaryText: Color(hex: 0xaaa095),
                accent: Color(hex: 0xef9185),
                subtleBackground: Color(hex: 0x24211d),
                border: Color(hex: 0x4b453e),
                blockQuoteBorder: Color(hex: 0x786d60),
                codeTheme: codeTheme
            )
        case (.diagramDown, false):
            PreviewTheme(
                id: "diagramdown-light",
                background: Color(hex: 0xffffff),
                primaryText: Color(hex: 0x172033),
                secondaryText: Color(hex: 0x657188),
                accent: Color(hex: 0x3767d6),
                subtleBackground: Color(hex: 0xf4f7fb),
                border: Color(hex: 0xd9e1ee),
                blockQuoteBorder: Color(hex: 0x8ba8e8),
                codeTheme: codeTheme
            )
        case (.diagramDown, true):
            PreviewTheme(
                id: "diagramdown-dark",
                background: Color(hex: 0x10141c),
                primaryText: Color(hex: 0xdce4f2),
                secondaryText: Color(hex: 0x98a5ba),
                accent: Color(hex: 0x8cbaff),
                subtleBackground: Color(hex: 0x151a23),
                border: Color(hex: 0x293345),
                blockQuoteBorder: Color(hex: 0x5579c4),
                codeTheme: codeTheme
            )
        }
    }
}

struct PreviewMetrics {
    let zoom: CGFloat

    var bodyFontSize: CGFloat { 15 * zoom }
    var codeFontSize: CGFloat { 13 * zoom }
    var blockSpacing: CGFloat { 14 * zoom }
    var documentHorizontalInset: CGFloat { 36 * zoom }
    var documentVerticalInset: CGFloat { 28 * zoom }
    var codeInset: CGFloat { 13 * zoom }
    var tableCellInset: CGFloat { 8 * zoom }
    var diagramMaximumHeight: CGFloat { 720 * zoom }

    func headingFontSize(level: Int) -> CGFloat {
        let sizes: [CGFloat] = [30, 25, 21, 18, 16, 15]
        return sizes[min(max(level - 1, 0), sizes.count - 1)] * zoom
    }
}

private extension Color {
    init(hex: UInt64) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: 1
        )
    }
}
