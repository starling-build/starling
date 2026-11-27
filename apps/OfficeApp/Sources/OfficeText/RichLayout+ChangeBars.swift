import Flutter
import FlutterSwiftBridge

extension RichLayout {
    /// The editor's change bars: a short upright line in the left margin beside every line that holds a tracked
    /// change (inserted or deleted text, a formatting change, an inserted paragraph mark or changed paragraph
    /// formatting), as Word shows them on screen. Screen only: the PDF's markup draws its own.
    public func canvasChangeBars(_ document: RichDocument, visible: Rect) -> [Rect] {
        var spans: [Rect] = []
        let n = min(count, document.paragraphs.count)
        for i in 0 ..< n {
            let p = document.paragraphs[i]
            var ranges: [Range<Int>] = []
            if p.style.markRevision != nil || p.style.propertyChange != nil {
                ranges.append(0 ..< p.text.utf16.count)
            }
            var at = 0
            for run in p.runs {
                if run.style.revision != nil || run.style.formatChange != nil {
                    if let last = ranges.last, last.upperBound >= at { ranges[ranges.count - 1] = last.lowerBound ..< max(last.upperBound, at + run.length) }
                    else { ranges.append(at ..< at + run.length) }
                }
                at += run.length
            }
            for r in ranges {
                let a = RichPosition(paragraph: i, offset: r.lowerBound), b = RichPosition(paragraph: i, offset: r.upperBound)
                var rects = r.isEmpty ? [] : canvasSelectionRects(RichSelection(anchor: a, focus: b), document)
                if rects.isEmpty { rects = [canvasCaretRect(a, document)] }
                for rect in rects where rect.bottom >= visible.top && rect.top <= visible.bottom {
                    spans.append(_changeBar(beside: rect))
                }
            }
        }
        return spans
    }

    private func _changeBar(beside line: Rect) -> Rect {
        let w = max(1, _px(0.75))
        var x = 2.0
        if isPaged {
            let pg = self.page(atCanvasY: line.center.dy)
            x = pageRect(pg).left + _pxMarginLeft(pg) - _px(9)
        }
        return Rect.fromLTWH(x, line.top, w, line.height)
    }
}
