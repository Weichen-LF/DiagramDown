//
//  LineNumberRulerView.swift
//  DiagramDown
//

import AppKit

final class LineNumberRulerView: NSView {
    private weak var scrollView: NSScrollView?
    private weak var textView: NSTextView?
    private var lineStartOffsets: [Int]?
    private(set) var preferredWidth: CGFloat = 44
    var preferredWidthDidChange: ((CGFloat) -> Void)?
    private let numberFont = NSFont.monospacedDigitSystemFont(
        ofSize: 11,
        weight: .regular
    )
    private let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        return style
    }()

    override var isFlipped: Bool {
        true
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.scrollView = scrollView
        self.textView = textView
        super.init(frame: .zero)
        updatePreferredWidth()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func invalidateLineStarts() {
        lineStartOffsets = nil
        updatePreferredWidth()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            drawSeparator(in: dirtyRect)
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let source = textView.string as NSString
        let offsets = resolvedLineStartOffsets(for: source)
        let selectedLine = lineNumber(
            forCharacterIndex: min(textView.selectedRange().location, source.length),
            offsets: offsets
        )
        let visibleRect = scrollView?.contentView.documentVisibleRect ?? textView.visibleRect
        let containerOrigin = textView.textContainerOrigin
        let containerVisibleRect = visibleRect.offsetBy(
            dx: -containerOrigin.x,
            dy: -containerOrigin.y
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
                    textView: textView,
                    dirtyRect: dirtyRect
                )
            }
        }

        if source.length == 0 || source.character(at: source.length - 1) == 10 {
            var extraLineRect = layoutManager.extraLineFragmentRect
            if extraLineRect.height <= 0 {
                extraLineRect.size.height = textView.font?.lineHeight ?? numberFont.lineHeight
            }
            drawLineNumber(
                offsets.count,
                lineRect: extraLineRect,
                selected: offsets.count == selectedLine,
                textView: textView,
                dirtyRect: dirtyRect
            )
        }

        drawSeparator(in: dirtyRect)
    }

    private func drawLineNumber(
        _ number: Int,
        lineRect: NSRect,
        selected: Bool,
        textView: NSTextView,
        dirtyRect: NSRect
    ) {
        let textPoint = NSPoint(
            x: 0,
            y: textView.textContainerOrigin.y + lineRect.minY
        )
        let rulerPoint = convert(textPoint, from: textView)
        let labelRect = NSRect(
            x: 4,
            y: rulerPoint.y + max((lineRect.height - numberFont.lineHeight) / 2, 0),
            width: max(preferredWidth - 12, 0),
            height: numberFont.lineHeight
        )
        guard labelRect.intersects(dirtyRect) else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: selected ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        String(number).draw(in: labelRect, withAttributes: attributes)
    }

    private func drawSeparator(in rect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(
            x: max(bounds.maxX - 1, 0),
            y: rect.minY,
            width: 1,
            height: rect.height
        ).fill()
    }

    private func updatePreferredWidth() {
        let source = (textView?.string ?? "") as NSString
        let lineCount = resolvedLineStartOffsets(for: source).count
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont]
        let numberWidth = ceil(
            (String(max(lineCount, 1)) as NSString).size(withAttributes: attributes).width
        )
        let newWidth = max(numberWidth + 20, 44)
        guard newWidth != preferredWidth else {
            return
        }
        preferredWidth = newWidth
        preferredWidthDidChange?(newWidth)
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
