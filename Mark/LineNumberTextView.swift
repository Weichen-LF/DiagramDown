//
//  LineNumberTextView.swift
//  DiagramDown
//

import AppKit

final class LineNumberTextView: NSTextView {
    private var lineStartOffsets: [Int]?
    private var gutterWidth: CGFloat = 44
    private let horizontalContentInset: CGFloat = 18
    private let verticalContentInset: CGFloat = 16
    private let numberFont = NSFont.monospacedDigitSystemFont(
        ofSize: 11,
        weight: .regular
    )
    private let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    convenience init() {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        self.init(frame: .zero, textContainer: textContainer)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        updateGutterWidth()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        updateGutterWidth()
    }

    func invalidateLineStarts() {
        lineStartOffsets = nil
        updateGutterWidth()
        invalidateLineNumberDisplay()
    }

    func invalidateLineNumberDisplay() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let graphicsContext = NSGraphicsContext.current else {
            return
        }
        graphicsContext.saveGraphicsState()
        defer { graphicsContext.restoreGraphicsState() }

        graphicsContext.cgContext.resetClip()
        graphicsContext.cgContext.clip(to: bounds)
        drawLineNumbers(in: visibleRect)
    }

    private func drawLineNumbers(in visibleRect: NSRect) {
        let gutterRect = NSRect(
            x: 0,
            y: visibleRect.minY,
            width: gutterWidth,
            height: visibleRect.height
        )
        NSColor.textBackgroundColor.setFill()
        gutterRect.fill()

        guard let layoutManager,
              let textContainer else {
            drawSeparator(in: visibleRect)
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let source = string as NSString
        let offsets = resolvedLineStartOffsets(for: source)
        let selectedLine = lineNumber(
            forCharacterIndex: min(selectedRange().location, source.length),
            offsets: offsets
        )
        let containerVisibleRect = visibleRect.offsetBy(
            dx: -textContainerOrigin.x,
            dy: -textContainerOrigin.y
        )
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: containerVisibleRect,
            in: textContainer
        )

        if visibleGlyphRange.length > 0 {
            layoutManager.enumerateLineFragments(
                forGlyphRange: visibleGlyphRange
            ) { [weak self] lineRect, _, _, glyphRange, _ in
                guard let self else {
                    return
                }

                let characterRange = layoutManager.characterRange(
                    forGlyphRange: glyphRange,
                    actualGlyphRange: nil
                )
                let number = self.lineNumber(
                    forCharacterIndex: characterRange.location,
                    offsets: offsets
                )
                guard offsets[number - 1] == characterRange.location else {
                    return
                }

                self.drawLineNumber(
                    number,
                    lineRect: lineRect,
                    selected: number == selectedLine,
                    visibleRect: visibleRect
                )
            }
        }

        if source.length == 0 || source.character(at: source.length - 1) == 10 {
            var extraLineRect = layoutManager.extraLineFragmentRect
            if extraLineRect.height <= 0 {
                extraLineRect.size.height = font?.lineHeight ?? numberFont.lineHeight
            }
            drawLineNumber(
                offsets.count,
                lineRect: extraLineRect,
                selected: offsets.count == selectedLine,
                visibleRect: visibleRect
            )
        }

        drawSeparator(in: visibleRect)
    }

    private func drawLineNumber(
        _ number: Int,
        lineRect: NSRect,
        selected: Bool,
        visibleRect: NSRect
    ) {
        let labelRect = NSRect(
            x: 4,
            y: textContainerOrigin.y
                + lineRect.minY
                + max((lineRect.height - numberFont.lineHeight) / 2, 0),
            width: max(gutterWidth - 12, 0),
            height: numberFont.lineHeight
        )
        guard labelRect.intersects(visibleRect) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: selected
                ? NSColor.secondaryLabelColor
                : NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        String(number).draw(in: labelRect, withAttributes: attributes)
    }

    private func drawSeparator(in visibleRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(
            x: max(gutterWidth - 1, 0),
            y: visibleRect.minY,
            width: 1,
            height: visibleRect.height
        ).fill()
    }

    private func updateGutterWidth() {
        let source = string as NSString
        let lineCount = resolvedLineStartOffsets(for: source).count
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont]
        let numberWidth = ceil(
            (String(max(lineCount, 1)) as NSString).size(withAttributes: attributes).width
        )
        gutterWidth = max(numberWidth + 20, 44)
        textContainerInset = NSSize(
            width: gutterWidth + horizontalContentInset,
            height: verticalContentInset
        )
    }

    private func resolvedLineStartOffsets(for source: NSString) -> [Int] {
        if let lineStartOffsets {
            return lineStartOffsets
        }

        var result = [0]
        if source.length > 0 {
            for index in 0..<source.length where source.character(at: index) == 10 {
                result.append(index + 1)
            }
        }
        lineStartOffsets = result
        return result
    }

    private func lineNumber(forCharacterIndex characterIndex: Int, offsets: [Int]) -> Int {
        var lowerBound = 0
        var upperBound = offsets.count
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if offsets[middle] <= characterIndex {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return max(lowerBound, 1)
    }
}

private extension NSFont {
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
