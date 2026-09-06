// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - Theme (Preview look: flat toolbar over a dark canvas)

private struct ViewerPalette {
    let background: Color      // window chrome
    let canvas: Color          // the surface behind the image
    let toolbar: Color
    let toolbarLine: Color
    let text: Color
    let dimText: Color
    let control: Color
    let controlText: Color
    let accent: Color

    init(dark: Bool) {
        if dark {
            background = Color(0xA6262930)
            canvas = Color(0xD91B1B1D)
            toolbar = Color(0xB32E3138)
            toolbarLine = Color(0x33000000)
            text = Color(0xFFE8E8E8)
            dimText = Color(0x88FFFFFF)
            control = Color(0x1FFFFFFF)
            controlText = Color(0xFFEEEEEE)
            accent = Color(0xFF0A84FF)
        } else {
            background = Color(0xCCECECEE)
            canvas = Color(0xE6DADADC)
            toolbar = Color(0xCCF3F3F5)
            toolbarLine = Color(0x22000000)
            text = Color(0xFF1D1D1F)
            dimText = Color(0x88000000)
            control = Color(0x10000000)
            controlText = Color(0xFF1D1D1F)
            accent = Color(0xFF007AFF)
        }
    }
}

// MARK: - X11 keysyms (as delivered in KeyData.logical by the DRM embedder)

private enum Keysym {
    static let left: Int64 = 0xFF51
    static let up: Int64 = 0xFF52
    static let right: Int64 = 0xFF53
    static let down: Int64 = 0xFF54
    static let escape: Int64 = 0xFF1B
    static let enter: Int64 = 0xFF0D
    static let delete: Int64 = 0xFFFF
}

// MARK: - Canvas painter

/// Fills the canvas and draws the image at its computed placement. Painting
/// with drawImageRect keeps zoom math exact (src is always the full image).
private class ImageCanvasPainter: CustomPainter {
    let image: Image?
    let dst: Rect
    let background: Color

    init(image: Image?, dst: Rect, background: Color) {
        self.image = image
        self.dst = dst
        self.background = background
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let bg = Paint()
        bg.color = background
        bg.style = .fill
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg)
        if let image {
            let paint = Paint()
            paint.filterQuality = .medium   // bilinear+mipmaps for scaling
            canvas.drawImageRect(
                image,
                Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)),
                dst,
                paint)
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        return true
    }
}

/// Continuous PDF layout: page cards (white, subtle border) at their
/// computed rects, with the rasterized bitmap over each when available.
private class PdfDocPainter: CustomPainter {
    let pages: [(rect: Rect, image: Image?)]
    let background: Color
    let overlayRect: Rect?         // in-progress highlight (canvas coords)
    let overlayPath: [Offset]      // in-progress ink stroke

    init(pages: [(rect: Rect, image: Image?)], background: Color,
         overlayRect: Rect? = nil, overlayPath: [Offset] = []) {
        self.pages = pages
        self.background = background
        self.overlayRect = overlayRect
        self.overlayPath = overlayPath
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let bg = Paint()
        bg.color = background
        bg.style = .fill
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg)
        let pagePaint = Paint()
        pagePaint.color = Color(0xFFFFFFFF)
        pagePaint.style = .fill
        for page in pages {
            let rect = page.rect
            if rect.top + rect.height < 0 || rect.top > size.height { continue }
            canvas.drawRect(rect, pagePaint)
            if let image = page.image {
                let paint = Paint()
                paint.filterQuality = .medium
                canvas.drawImageRect(
                    image,
                    Rect.fromLTWH(0, 0, Double(image.width),
                                  Double(image.height)),
                    rect, paint)
            }
        }
        if let overlayRect {
            let paint = Paint()
            paint.color = Color(0x66FFD633)
            paint.style = .fill
            canvas.drawRect(overlayRect, paint)
        }
        if overlayPath.count >= 2 {
            let paint = Paint()
            paint.color = Color(0xE0E03131)
            paint.style = .stroke
            paint.strokeWidth = 2.5
            let path = Path()
            path.moveTo(overlayPath[0].dx, overlayPath[0].dy)
            for point in overlayPath.dropFirst() {
                path.lineTo(point.dx, point.dy)
            }
            canvas.drawPath(path, paint)
        }
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        return true
    }
}

/// One sidebar thumbnail: white page card, rasterized page when available,
/// accent border for the current page.
private class ThumbPainter: CustomPainter {
    let image: Image?
    let selected: Bool
    let accent: Color

    init(image: Image?, selected: Bool, accent: Color) {
        self.image = image
        self.selected = selected
        self.accent = accent
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let card = Rect.fromLTWH(0, 0, size.width, size.height)
        let fill = Paint()
        fill.color = Color(0xFFFFFFFF)
        fill.style = .fill
        canvas.drawRect(card, fill)
        if let image {
            let paint = Paint()
            paint.filterQuality = .medium
            canvas.drawImageRect(
                image,
                Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)),
                card, paint)
        }
        let border = Paint()
        border.color = selected ? accent : Color(0x33000000)
        border.style = .stroke
        border.strokeWidth = selected ? 2.5 : 1
        canvas.drawRect(card, border)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        return true
    }
}

/// Transfers a decoded Image to the main queue (single hand-off).
private final class _ImageBox: @unchecked Sendable {
    let image: Image
    init(_ image: Image) { self.image = image }
}

// MARK: - ImageViewerApp

class ImageViewerApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _ImageViewerAppState()
    }
}

class _ImageViewerAppState: State<StatefulWidget>, @unchecked Sendable {

    private var pal = ViewerPalette(dark: true)
    private let viewerFocus = FocusNode(debugLabel: "ImageViewer")

    // Current image + its file
    private var image: Image? = nil
    private var path: String = ""
    private var statusMessage = ""

    // Sibling images of the current file's folder, for ‹ › navigation.
    private var dirImages: [String] = []
    private var dirIndex: Int = -1

    /// nil = fit-to-window; otherwise an explicit scale (1.0 = 100%).
    private var zoom: Double? = nil
    private var panX: Double = 0
    private var panY: Double = 0

    private var _dragging = false
    private var _lastDragPos = Offset.zero
    private var _lastClickAt: Double = 0
    private var ctrlDown = false

    // PDF mode (Linux/PDFium). When set, ‹ › walk pages, not files.
    #if os(Linux)
    private var pdf: PdfDocument? = nil
    #endif
    private var pdfPage = 0
    private var pdfPageCount = 0
    /// Page sizes in PDF points, prefetched at load (drives layout without
    /// touching PDFium per frame).
    private var pdfPageSizes: [(width: Double, height: Double)] = []
    /// Rasterized pages (visible window only) and the scale each was
    /// rendered at (pixels per point).
    private var pdfImages: [Int: Image] = [:]
    private var pdfImageScale: [Int: Double] = [:]
    private var _pdfInflight: Set<Int> = []
    /// Pages whose cached bitmap shows outdated content (form edit,
    /// annotation) but is still the right size — kept on screen while the
    /// replacement renders. Cleared when the re-render snapshots the page.
    private var _pdfDirty: Set<Int> = []
    // Thumbnail sidebar
    private var _sidebarOpen = true
    private var _thumbScroll: Double = 0
    private var pdfThumbs: [Int: Image] = [:]
    private var _thumbInflight: Set<Int> = []
    private var _thumbDirty: Set<Int> = []
    private var _lastIndicatedPage = -1
    private var pdfModified = false
    // Annotation tools
    private enum PdfTool { case none, highlight, ink }
    private var pdfTool: PdfTool = .none
    private var _annotPage: Int? = nil
    private var _annotStart = Offset.zero
    private var _annotCurrent = Offset.zero
    private var _inkPoints: [Offset] = []
    /// Page whose form text field currently has keyboard focus.
    private var _formFocusPage: Int? = nil

    // File picker
    private var _pickerOpen = false
    private var _pickerDir = NSHomeDirectory()
    private var _pickerEntries: [(name: String, isDir: Bool)] = []
    private var _pickerScroll: Double = 0

    private let toolbarHeight: Double = 46

    static let kImageExts: Set<String> = ["png", "jpg", "jpeg", "gif",
                                          "webp", "bmp"]
    /// Everything the picker offers (images + PDFs on Linux).
    static let kOpenExts: Set<String> = {
        var exts = kImageExts
        #if os(Linux)
        exts.insert("pdf")
        #endif
        return exts
    }()

    override func initState() {
        super.initState()
        viewerFocus.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        viewerFocus.requestFocus()

        // `ImageViewerApp <path>` opens the file at startup.
        let args = CommandLine.arguments
        if args.count > 1 && !args[1].hasPrefix("-") {
            _load(args[1])
        }
    }

    override func dispose() {
        viewerFocus.dispose()
        image?.dispose()
        for (_, img) in pdfImages { img.dispose() }
        for (_, img) in pdfThumbs { img.dispose() }
        super.dispose()
    }

    // MARK: - Geometry

    private func _viewLogicalSize() -> Size {
        if let view = PlatformDispatcher.instance.implicitView {
            let dpr = view.devicePixelRatio
            let phys = view.physicalSize
            if phys.width > 0 && phys.height > 0 && dpr > 0 {
                return Size(phys.width / dpr, phys.height / dpr)
            }
        }
        return Size(900, 620)
    }

    private func _sidebarVisible() -> Bool {
        #if os(Linux)
        return pdf != nil && _sidebarOpen && pdfPageCount > 1
        #else
        return false
        #endif
    }

    private func _canvasSize() -> Size {
        let size = _viewLogicalSize()
        let width = size.width - (_sidebarVisible() ? sidebarWidth + 1 : 0)
        return Size(max(0, width), max(0, size.height - toolbarHeight))
    }

    private func _fitScale(_ canvas: Size) -> Double {
        guard let image, image.width > 0, image.height > 0 else { return 1 }
        return min(canvas.width / Double(image.width),
                   canvas.height / Double(image.height))
    }

    /// Display scale: image pixels per logical pixel for bitmaps, PDF
    /// points per logical pixel for PDFs (so 100% = one point per pixel).
    private func _scale(_ canvas: Size) -> Double {
        #if os(Linux)
        if pdf != nil { return zoom ?? _pdfFitScale(canvas) }
        #endif
        return zoom ?? _fitScale(canvas)
    }

    /// Image placement in canvas coordinates: centered, plus the pan offset
    /// (clamped so the image can never be dragged fully off screen).
    private func _imageRect(_ canvas: Size) -> Rect {
        guard let image else { return Rect.fromLTWH(0, 0, 0, 0) }
        let scale = _scale(canvas)
        let w = Double(image.width) * scale
        let h = Double(image.height) * scale
        let maxPanX = max(0, (w - canvas.width) / 2)
        let maxPanY = max(0, (h - canvas.height) / 2)
        panX = max(-maxPanX, min(maxPanX, panX))
        panY = max(-maxPanY, min(maxPanY, panY))
        return Rect.fromLTWH((canvas.width - w) / 2 + panX,
                             (canvas.height - h) / 2 + panY, w, h)
    }

    // MARK: - Loading

    private func _load(_ rawPath: String) {
        let expanded = NSString(string: rawPath).expandingTildeInPath
        #if os(Linux)
        if (expanded as NSString).pathExtension.lowercased() == "pdf" {
            _loadPdf(expanded)
            return
        }
        _closePdf()
        #endif
        guard let data = FileManager.default.contents(atPath: expanded) else {
            setState { statusMessage = "Cannot read \(expanded)" }
            return
        }
        setState { statusMessage = "Loading…" }
        Task { @MainActor [weak self] in
            do {
                // ui-level codec (PaintingBinding is not wired in this port)
                let codec = try await FlutterSwiftBridge.instantiateImageCodec([UInt8](data))
                let frame = try await codec.getNextFrame()
                codec.dispose()
                let decoded = frame.image
                guard let self else {
                    decoded.dispose()
                    return
                }
                self.setState {
                    self.image?.dispose()
                    self.image = decoded
                    self.path = expanded
                    self.zoom = nil
                    self.panX = 0
                    self.panY = 0
                    self.statusMessage = ""
                    self._scanSiblings(of: expanded)
                }
            } catch {
                self?.setState {
                    self?.statusMessage = "Cannot decode \((expanded as NSString).lastPathComponent)"
                }
            }
        }
    }

    #if os(Linux)
    // MARK: - PDF (continuous multi-page layout, windowed rendering)

    private let pdfPageGap: Double = 14

    private func _pdfFitScale(_ canvas: Size) -> Double {
        guard let first = pdfPageSizes.first,
              first.width > 0, first.height > 0 else { return 1 }
        return min(canvas.width / first.width, canvas.height / first.height)
    }

    /// Content-relative page rects (display px) plus the total content size:
    /// pages stacked vertically with gaps, each centered horizontally.
    private func _pdfLayout(_ canvas: Size) -> (rects: [Rect], content: Size) {
        let scale = _scale(canvas)
        var rects: [Rect] = []
        rects.reserveCapacity(pdfPageSizes.count)
        var y = 0.0
        var maxW = 0.0
        for pts in pdfPageSizes {
            let w = pts.width * scale
            let h = pts.height * scale
            rects.append(Rect.fromLTWH(0, y, w, h))
            maxW = max(maxW, w)
            y += h + pdfPageGap
        }
        let totalH = max(0, y - pdfPageGap)
        rects = rects.map {
            Rect.fromLTWH((maxW - $0.width) / 2, $0.top, $0.width, $0.height)
        }
        return (rects, Size(maxW, totalH))
    }

    /// Top-left of the content box in canvas coords (clamps the pan).
    private func _pdfContentOrigin(_ canvas: Size, _ content: Size) -> Offset {
        let maxPanX = max(0, (content.width - canvas.width) / 2)
        let maxPanY = max(0, (content.height - canvas.height) / 2)
        panX = max(-maxPanX, min(maxPanX, panX))
        panY = max(-maxPanY, min(maxPanY, panY))
        return Offset((canvas.width - content.width) / 2 + panX,
                      (canvas.height - content.height) / 2 + panY)
    }

    /// The page under the viewport center drives the toolbar indicator.
    private func _updateCurrentPdfPage(rects: [Rect], origin: Offset,
                                       canvas: Size) {
        let centerY = canvas.height / 2 - origin.dy
        for (i, rect) in rects.enumerated()
        where centerY < rect.top + rect.height + pdfPageGap / 2 {
            pdfPage = i
            return
        }
        pdfPage = max(0, rects.count - 1)
    }

    /// Rasterization scale for one page, memory-capped.
    private func _cappedPageScale(_ page: Int, _ target: Double) -> Double {
        let pts = pdfPageSizes[page]
        var scale = target
        let maxSide = max(pts.width, pts.height)
        if maxSide > 0 { scale = min(scale, 6144 / maxSide) }
        let pixels = pts.width * pts.height * scale * scale
        if pixels > 28_000_000 { scale *= (28_000_000 / pixels).squareRoot() }
        return scale
    }

    /// Runs on every PDF build: render the visible pages (±1) whose backing
    /// resolution is missing or >20% off the current zoom, evict pages far
    /// outside the viewport. Cheap when nothing changed.
    private func _ensurePdfPages(canvas: Size, rects: [Rect], origin: Offset) {
        guard pdf != nil, !rects.isEmpty else { return }
        var firstVisible = -1
        var lastVisible = -1
        for (i, rect) in rects.enumerated() {
            let top = origin.dy + rect.top
            if top + rect.height >= 0 && top <= canvas.height {
                if firstVisible < 0 { firstVisible = i }
                lastVisible = i
            }
        }
        if firstVisible < 0 { firstVisible = 0; lastVisible = 0 }
        let lo = max(0, firstVisible - 1)
        let hi = min(pdfPageSizes.count - 1, lastVisible + 1)

        for (page, img) in pdfImages where page < lo - 1 || page > hi + 1 {
            img.dispose()
            pdfImages.removeValue(forKey: page)
            pdfImageScale.removeValue(forKey: page)
        }

        let dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2
        // Rasterize at exactly the displayed physical resolution: 1:1
        // pixels beats over-rendering + downscaling for text clarity.
        let base = max(0.5, _scale(canvas) * dpr)
        // One render per build pass: each decode callback's setState runs
        // the pass again, so the queue drains itself — serialized decodes
        // instead of a burst at open.
        for page in lo ... hi {
            let target = _cappedPageScale(page, base)
            let rendered = pdfImageScale[page]
            let stale = rendered == nil || abs(rendered! / target - 1) > 0.2
                || _pdfDirty.contains(page)
            if stale && !_pdfInflight.contains(page) {
                _renderPdfPageAsync(page, scale: target)
                break
            }
        }
    }

    private func _renderPdfPageAsync(_ page: Int, scale: Double) {
        guard let pdf else { return }
        _pdfInflight.insert(page)
        let pts = pdfPageSizes[page]
        let width = Int(pts.width * scale)
        let height = Int(pts.height * scale)
        guard let pixels = pdf.render(page: page, width: width,
                                      height: height) else {
            _pdfInflight.remove(page)
            return
        }
        // The snapshot above is synchronous, so the dirty flag is settled
        // here — an edit landing during the async decode below re-dirties
        // the page and triggers another pass.
        _pdfDirty.remove(page)
        decodeImageFromPixels(pixels, width: width, height: height,
                              format: .bgra8888, callback: { [weak self] decoded in
            guard let self, self.pdf != nil,
                  page < self.pdfPageSizes.count else {
                decoded.dispose()
                return
            }
            // Decode callbacks can arrive off the UI thread, where setState
            // marks state dirty but schedules no frame — the progressive
            // render chain then stalls until unrelated input arrives.
            let box = _ImageBox(decoded)
            DispatchQueue.main.async {
                self.setState {
                    self._pdfInflight.remove(page)
                    self.pdfImages[page]?.dispose()
                    self.pdfImages[page] = box.image
                    self.pdfImageScale[page] = scale
                }
            }
        })
    }

    private func _loadPdf(_ expanded: String) {
        guard let document = PdfDocument(path: expanded) else {
            setState { statusMessage = "Cannot open \((expanded as NSString).lastPathComponent)" }
            return
        }
        _closePdf()
        image?.dispose()
        image = nil
        pdf = document
        pdfPageCount = document.pageCount
        pdfPageSizes = (0 ..< document.pageCount).map { document.pageSize($0) }
        path = expanded
        dirImages = []
        dirIndex = -1
        setState {
            zoom = nil
            panX = 0
            // pan 0 centers the whole page column — start at page 1's top.
            let canvas = _canvasSize()
            let (_, content) = _pdfLayout(canvas)
            panY = max(0, (content.height - canvas.height) / 2)
            statusMessage = ""
        }
    }

    private func _closePdf() {
        pdf = nil
        pdfPage = 0
        pdfPageCount = 0
        pdfPageSizes = []
        for (_, img) in pdfImages { img.dispose() }
        pdfImages = [:]
        pdfImageScale = [:]
        _pdfInflight = []
        _pdfDirty = []
        for (_, img) in pdfThumbs { img.dispose() }
        pdfThumbs = [:]
        _thumbInflight = []
        _thumbDirty = []
        _thumbScroll = 0
        _lastIndicatedPage = -1
        pdfModified = false
        pdfTool = .none
        _annotPage = nil
        _inkPoints = []
        _formFocusPage = nil
    }

    // MARK: - Page editing (rotate / delete / reorder / save)

    /// Invalidate cached bitmaps after an edit. The single-page form keeps
    /// the stale bitmap on screen and marks it dirty — the re-render swaps
    /// it in place, instead of flashing a blank card on every form
    /// keystroke. `dropBitmap: true` discards it immediately, for edits
    /// where the old pixels aren't even approximately right (rotate flips
    /// the aspect). The no-arg form drops everything: delete/move shift
    /// page indices, so every cached bitmap is suspect.
    private func _invalidatePdfCaches(page: Int? = nil,
                                      dropBitmap: Bool = false) {
        if let page {
            if dropBitmap {
                pdfImages[page]?.dispose()
                pdfImages.removeValue(forKey: page)
                pdfImageScale.removeValue(forKey: page)
                pdfThumbs[page]?.dispose()
                pdfThumbs.removeValue(forKey: page)
                _pdfDirty.remove(page)
                _thumbDirty.remove(page)
            } else {
                _pdfDirty.insert(page)
                _thumbDirty.insert(page)
            }
        } else {
            for (_, img) in pdfImages { img.dispose() }
            pdfImages = [:]
            pdfImageScale = [:]
            _pdfDirty = []
            for (_, img) in pdfThumbs { img.dispose() }
            pdfThumbs = [:]
            _thumbDirty = []
        }
    }

    /// Map a canvas point to (page index, unrotated page points), honoring
    /// the page's /Rotate. Returns nil outside every page.
    private func _pagePoint(at canvasPoint: Offset,
                            rects: [Rect], origin: Offset,
                            clampTo page: Int? = nil) -> (page: Int, x: Double, y: Double)? {
        guard let pdf else { return nil }
        func map(_ index: Int) -> (page: Int, x: Double, y: Double) {
            let rect = rects[index]
            let left = origin.dx + rect.left
            let top = origin.dy + rect.top
            var u = rect.width > 0 ? (canvasPoint.dx - left) / rect.width : 0
            var v = rect.height > 0 ? (canvasPoint.dy - top) / rect.height : 0
            u = max(0, min(1, u))
            v = max(0, min(1, v))
            // pdfPageSizes holds the ROTATED (displayed) size; annotation
            // space is unrotated.
            let disp = pdfPageSizes[index]
            let rot = pdf.pageRotation(index)
            let w = rot % 2 == 0 ? disp.width : disp.height
            let h = rot % 2 == 0 ? disp.height : disp.width
            switch rot {
            case 1: return (index, v * w, u * h)
            case 2: return (index, (1 - u) * w, v * h)
            case 3: return (index, (1 - v) * w, (1 - u) * h)
            default: return (index, u * w, (1 - v) * h)
            }
        }
        if let page {
            return map(page)
        }
        for (i, rect) in rects.enumerated() {
            let top = origin.dy + rect.top
            let left = origin.dx + rect.left
            if canvasPoint.dx >= left, canvasPoint.dx <= left + rect.width,
               canvasPoint.dy >= top, canvasPoint.dy <= top + rect.height {
                return map(i)
            }
        }
        return nil
    }

    /// Commit the finished drag as an annotation on the captured page.
    private func _finishAnnotation() {
        guard let pdf, let page = _annotPage else { return }
        let canvas = _canvasSize()
        let (rects, content) = _pdfLayout(canvas)
        let origin = _pdfContentOrigin(canvas, content)
        guard page < rects.count else { _annotPage = nil; return }
        var changed = false
        switch pdfTool {
        case .highlight:
            if let a = _pagePoint(at: _annotStart, rects: rects,
                                  origin: origin, clampTo: page),
               let b = _pagePoint(at: _annotCurrent, rects: rects,
                                  origin: origin, clampTo: page),
               abs(a.x - b.x) > 2, abs(a.y - b.y) > 2 {
                changed = pdf.addHighlight(page: page,
                                           minX: min(a.x, b.x),
                                           minY: min(a.y, b.y),
                                           maxX: max(a.x, b.x),
                                           maxY: max(a.y, b.y))
            }
        case .ink:
            let mapped = _inkPoints.compactMap {
                _pagePoint(at: $0, rects: rects, origin: origin, clampTo: page)
            }.map { (x: $0.x, y: $0.y) }
            if mapped.count >= 2 {
                changed = pdf.addInk(page: page, points: mapped)
            }
        case .none:
            break
        }
        setState {
            _annotPage = nil
            _inkPoints = []
            if changed {
                _invalidatePdfCaches(page: page)
                pdfModified = true
                statusMessage = ""
            }
        }
    }

    private func _rotateCurrentPage() {
        guard let pdf, pdfPage < pdfPageCount else { return }
        pdf.rotatePage(pdfPage)
        setState {
            pdfPageSizes[pdfPage] = pdf.pageSize(pdfPage)
            // The aspect flipped — the old bitmap would paint 90° wrong.
            _invalidatePdfCaches(page: pdfPage, dropBitmap: true)
            pdfModified = true
            statusMessage = ""
        }
    }

    private func _deleteCurrentPage() {
        guard let pdf, pdfPageCount > 1, pdfPage < pdfPageCount else { return }
        pdf.deletePage(pdfPage)
        setState {
            pdfPageSizes.remove(at: pdfPage)
            pdfPageCount -= 1
            // Indices shifted — every cached bitmap is suspect.
            _invalidatePdfCaches()
            pdfPage = min(pdfPage, pdfPageCount - 1)
            _lastIndicatedPage = -1
            pdfModified = true
            statusMessage = ""
        }
    }

    private func _moveCurrentPage(_ delta: Int) {
        guard let pdf, pdfPageCount > 1 else { return }
        let dest = pdfPage + delta
        guard dest >= 0, dest < pdfPageCount,
              pdf.movePage(pdfPage, to: dest) else { return }
        setState {
            pdfPageSizes.swapAt(pdfPage, dest)
            _invalidatePdfCaches()
            pdfModified = true
            _lastIndicatedPage = -1
            statusMessage = ""
        }
        _scrollToPage(dest)
    }

    private func _savePdf() {
        guard let pdf else { return }
        let focused = _formFocusPage
        let ok = pdf.save(to: path)     // commits any in-edit field first
        setState {
            _formFocusPage = nil
            if let focused { _invalidatePdfCaches(page: focused) }
            if ok { pdfModified = false }
            statusMessage = ok ? "Saved" : "Save failed"
        }
    }

    /// Scroll the main view so `index`'s page top sits just below the
    /// toolbar (‹ ›, arrow keys, thumbnail clicks).
    private func _scrollToPage(_ index: Int) {
        let canvas = _canvasSize()
        let (rects, content) = _pdfLayout(canvas)
        guard index >= 0, index < rects.count else { return }
        setState {
            pdfPage = index
            panY = (content.height - canvas.height) / 2 - rects[index].top + 6
        }
    }

    // MARK: - Thumbnail sidebar

    private let sidebarWidth: Double = 152
    private let thumbCellW: Double = 112
    private let thumbGap: Double = 14
    private let thumbLabelH: Double = 20

    private func _thumbCellHeights() -> [Double] {
        pdfPageSizes.map { pts in
            let aspect = pts.width > 0 ? pts.height / pts.width : 1.4
            return min(220, max(40, thumbCellW * aspect)) + thumbLabelH + thumbGap
        }
    }

    private func _sidebarView() -> Widget {
        let viewH = max(0, _viewLogicalSize().height - toolbarHeight)
        let heights = _thumbCellHeights()
        var offsets: [Double] = []
        offsets.reserveCapacity(heights.count)
        var y = thumbGap / 2
        for h in heights {
            offsets.append(y)
            y += h
        }
        let maxScroll = max(0, y - viewH)

        // Follow the current page when the MAIN view changes it.
        if pdfPage != _lastIndicatedPage, pdfPage < offsets.count {
            _lastIndicatedPage = pdfPage
            let top = offsets[pdfPage]
            let bottom = top + heights[pdfPage]
            if top - 8 < _thumbScroll {
                _thumbScroll = max(0, top - 8)
            } else if bottom > _thumbScroll + viewH {
                _thumbScroll = bottom - viewH + 8
            }
        }
        _thumbScroll = max(0, min(_thumbScroll, maxScroll))

        var first = 0
        while first < offsets.count - 1, offsets[first + 1] <= _thumbScroll {
            first += 1
        }
        var rows: [Widget] = []
        var last = first
        var i = first
        while i < heights.count, offsets[i] < _thumbScroll + viewH {
            rows.append(_thumbRow(i, cellHeight: heights[i]))
            last = i
            i += 1
        }
        _ensureThumbs(first: first, last: last)

        return SizedBox(width: sidebarWidth, child: ColoredBox(
            color: pal.toolbar,
            child: Listener(
                onPointerSignal: { [self] event in
                    guard let scroll = event as? PointerScrollEvent else { return }
                    let target = max(0, min(_thumbScroll + scroll.scrollDelta.dy,
                                            maxScroll))
                    if target != _thumbScroll {
                        setState { _thumbScroll = target }
                    }
                },
                behavior: .opaque,
                child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: 0)),
                    child: Stack(children: [
                        Positioned(
                            left: 0,
                            top: (offsets.isEmpty ? 0 : offsets[first]) - _thumbScroll,
                            right: 0,
                            child: Column(mainAxisSize: .min, children: rows)
                        ),
                    ])
                )
            )
        ))
    }

    private func _thumbRow(_ page: Int, cellHeight: Double) -> Widget {
        let selected = page == pdfPage
        let cardH = cellHeight - thumbLabelH - thumbGap
        return GestureDetector(
            onTap: { [self] in _scrollToPage(page) },
            behavior: .opaque,
            child: SizedBox(width: sidebarWidth, height: cellHeight, child:
                Column(children: [
                    SizedBox(width: thumbCellW, height: cardH, child:
                        CustomPaint(
                            painter: ThumbPainter(image: pdfThumbs[page],
                                                  selected: selected,
                                                  accent: pal.accent),
                            child: SizedBox(expand: ()))),
                    SizedBox(height: 3),
                    Text("\(page + 1)", style: TextStyle(
                        color: selected ? pal.accent : pal.dimText,
                        fontSize: 11)),
                ])
            )
        )
    }

    /// Render thumbnails for the visible rows (±2); evict far ones.
    private func _ensureThumbs(first: Int, last: Int) {
        guard let pdf, !pdfPageSizes.isEmpty, first <= last else { return }
        let lo = max(0, first - 2)
        let hi = min(pdfPageSizes.count - 1, last + 2)
        for (page, img) in pdfThumbs where page < lo - 8 || page > hi + 8 {
            img.dispose()
            pdfThumbs.removeValue(forKey: page)
        }
        let dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 2
        // One thumb per pass (see _ensurePdfPages).
        for page in lo ... hi
        where (pdfThumbs[page] == nil || _thumbDirty.contains(page))
            && !_thumbInflight.contains(page) {
            let pts = pdfPageSizes[page]
            guard pts.width > 0 else { continue }
            let scale = thumbCellW * dpr / pts.width
            let width = Int(pts.width * scale)
            let height = Int(pts.height * scale)
            _thumbInflight.insert(page)
            guard let pixels = pdf.render(page: page, width: width,
                                          height: height) else {
                _thumbInflight.remove(page)
                continue
            }
            _thumbDirty.remove(page)   // snapshot taken; later edits re-dirty
            decodeImageFromPixels(pixels, width: width, height: height,
                                  format: .bgra8888, callback: { [weak self] decoded in
                guard let self, self.pdf != nil,
                      page < self.pdfPageSizes.count else {
                    decoded.dispose()
                    return
                }
                let box = _ImageBox(decoded)
                DispatchQueue.main.async {
                    self.setState {
                        self._thumbInflight.remove(page)
                        self.pdfThumbs[page]?.dispose()
                        self.pdfThumbs[page] = box.image
                    }
                }
            })
            break
        }
    }
    #endif

    /// Collect the folder's images (sorted) so ‹ › can walk them.
    private func _scanSiblings(of file: String) {
        let dir = (file as NSString).deletingLastPathComponent
        let base = (file as NSString).lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        dirImages = names
            .filter { Self.kImageExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.lowercased() < $1.lowercased() }
            .map { dir + "/" + $0 }
        dirIndex = dirImages.firstIndex { ($0 as NSString).lastPathComponent == base } ?? -1
    }

    private func _step(_ delta: Int) {
        #if os(Linux)
        if pdf != nil {
            let target = max(0, min(pdfPageCount - 1, pdfPage + delta))
            guard target != pdfPage else { return }
            _scrollToPage(target)
            return
        }
        #endif
        guard !dirImages.isEmpty else { return }
        let target = dirIndex < 0 ? 0
            : max(0, min(dirImages.count - 1, dirIndex + delta))
        guard target != dirIndex || dirIndex < 0 else { return }
        _load(dirImages[target])
    }

    // MARK: - Zoom

    private func _setZoom(_ target: Double) {
        let canvas = _canvasSize()
        var maxZoom = 32.0
        #if os(Linux)
        if pdf != nil { maxZoom = 8 }
        #endif
        let clamped = max(0.05, min(maxZoom, target))
        // Keep the current center: pan scales with the zoom ratio.
        let ratio = clamped / _scale(canvas)
        zoom = clamped
        panX *= ratio
        panY *= ratio
    }

    private func _zoomStep(_ factor: Double) {
        setState {
            _setZoom(_scale(_canvasSize()) * factor)
            statusMessage = ""
        }
    }

    private func _zoomLabel() -> String {
        "\(Int((_scale(_canvasSize()) * 100).rounded()))%"
    }

    // MARK: - Keys

    private func _handleKey(_ keyData: KeyData) -> Bool {
        if keyData.logical == 0xFFE3 || keyData.logical == 0xFFE4 {
            ctrlDown = (keyData.type == .down || keyData.type == .repeat)
            return false
        }
        guard keyData.type == .down || keyData.type == .repeat else { return false }

        if _pickerOpen {
            if keyData.logical == Keysym.escape {
                setState { _pickerOpen = false }
            }
            return true
        }

        #if os(Linux)
        // A focused form field owns the keyboard.
        if let pdf, let page = _formFocusPage {
            var handledByForm = true
            switch keyData.logical {
            case Keysym.escape:
                pdf.killFormFocus()
                _formFocusPage = nil
            case 0xFF08:                      // backspace
                pdf.formChar(page: page, 8)
            case Keysym.enter:
                pdf.formChar(page: page, 13)
            case Keysym.left:
                pdf.formKey(page: page, 0x25)
            case Keysym.right:
                pdf.formKey(page: page, 0x27)
            case Keysym.delete:
                pdf.formKey(page: page, 0x2E)
            default:
                if let character = keyData.character,
                   let scalar = character.unicodeScalars.first {
                    if scalar.value == 0x01 || (ctrlDown && (character == "a" || character == "A")) {
                        pdf.formSelectAll(page: page)     // Ctrl+A
                    } else if scalar.value >= 0x20, scalar.value != 0x7F, !ctrlDown {
                        for unit in character.utf16 {
                            pdf.formChar(page: page, Int(unit))
                        }
                    } else {
                        handledByForm = false
                    }
                } else {
                    handledByForm = false
                }
            }
            if handledByForm {
                setState {
                    _invalidatePdfCaches(page: page)
                    pdfModified = true
                }
                return true
            }
            return false
        }
        #endif

        switch keyData.logical {
        case Keysym.left, Keysym.up:
            _step(-1)
            return true
        case Keysym.right, Keysym.down:
            _step(1)
            return true
        default:
            break
        }

        guard let character = keyData.character,
              let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0F:                         // Ctrl+O
            _openPicker()
        case UInt32(UInt8(ascii: "+")), UInt32(UInt8(ascii: "=")):
            _zoomStep(1.25)
        case UInt32(UInt8(ascii: "-")):
            _zoomStep(1 / 1.25)
        case UInt32(UInt8(ascii: "0")):
            setState { zoom = nil; panX = 0; panY = 0 }
        case UInt32(UInt8(ascii: "1")):
            setState { _setZoom(1) }
        default:
            if ctrlDown && (character == "o" || character == "O") {
                _openPicker()
            } else {
                return false
            }
        }
        return true
    }

    // MARK: - Build

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        pal = ViewerPalette(dark: theme.brightness == .dark)

        // Build the canvas FIRST: it updates the current-page indicator the
        // sidebar highlights and follows.
        let canvasWidget = _canvasView()
        var body: [Widget] = []
        #if os(Linux)
        if _sidebarVisible() {
            body.append(_sidebarView())
            body.append(SizedBox(width: 1, child: ColoredBox(
                color: pal.toolbarLine, child: SizedBox(expand: ()))))
        }
        #endif
        body.append(Expanded(child: canvasWidget))

        var layers: [Widget] = [
            ColoredBox(
                color: pal.background,
                child: Column(children: [
                    _toolbar(),
                    Expanded(child: Row(children: body)),
                ])
            )
        ]
        if _pickerOpen {
            layers.append(_pickerOverlay())
        }
        return Stack(children: layers)
    }

    // MARK: - Toolbar

    private func _toolbar() -> Widget {
        let name = path.isEmpty ? "" : (path as NSString).lastPathComponent
        var title = name.isEmpty ? "No image" : name
        var isPdf = false
        #if os(Linux)
        isPdf = pdf != nil
        #endif
        if isPdf {
            title += "  —  page \(pdfPage + 1)/\(pdfPageCount)"
        } else {
            let dims = image.map { "\($0.width)×\($0.height)" } ?? ""
            if !dims.isEmpty { title += "  —  \(dims)" }
            if !dirImages.isEmpty && dirIndex >= 0 {
                title += "  (\(dirIndex + 1)/\(dirImages.count))"
            }
        }

        return SizedBox(
            height: toolbarHeight,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.toolbar,
                    border: Border(bottom: BorderSide(color: pal.toolbarLine, width: 1))
                ),
                child: Padding(
                    padding: EdgeInsets(horizontal: 10, vertical: 8),
                    child: Row(children: [
                        _barButton("Open") { [self] in _openPicker() },
                        _sidebarToggle(),
                        SizedBox(width: 10),
                        _barButton("‹") { [self] in _step(-1) },
                        SizedBox(width: 4),
                        _barButton("›") { [self] in _step(1) },
                        SizedBox(width: 10),
                        _barButton("−") { [self] in _zoomStep(1 / 1.25) },
                        SizedBox(width: 5),
                        SizedBox(width: 44, child: Center(child:
                            Text(_zoomLabel(), style: TextStyle(
                                color: pal.controlText, fontSize: 12)))),
                        SizedBox(width: 5),
                        _barButton("+") { [self] in _zoomStep(1.25) },
                        SizedBox(width: 10),
                        _barButton("Fit") { [self] in
                            setState { zoom = nil; panX = 0; panY = 0 }
                        },
                        SizedBox(width: 4),
                        _barButton("1:1") { [self] in
                            setState { _setZoom(1) }
                        },
                        SizedBox(width: 12),
                        Expanded(child: Text(
                            statusMessage.isEmpty ? title : statusMessage,
                            style: TextStyle(
                                color: statusMessage.isEmpty ? pal.dimText
                                                             : pal.text,
                                fontSize: 12),
                            maxLines: 1)),
                    ])
                )
            )
        )
    }

    /// Sidebar show/hide + page-editing buttons, PDF-only.
    private func _sidebarToggle() -> Widget {
        #if os(Linux)
        if pdf != nil {
            var items: [Widget] = []
            if pdfPageCount > 1 {
                items += [
                    SizedBox(width: 6),
                    _barButton("Pages") { [self] in
                        setState { _sidebarOpen.toggle() }
                    },
                ]
            }
            items += [
                SizedBox(width: 6),
                _barButton("Rotate") { [self] in _rotateCurrentPage() },
            ]
            if pdfPageCount > 1 {
                items += [
                    SizedBox(width: 4),
                    _barButton("Up") { [self] in _moveCurrentPage(-1) },
                    SizedBox(width: 4),
                    _barButton("Down") { [self] in _moveCurrentPage(1) },
                    SizedBox(width: 4),
                    _barButton("Del") { [self] in _deleteCurrentPage() },
                ]
            }
            items += [
                SizedBox(width: 6),
                _toolButton("Mark", active: pdfTool == .highlight) { [self] in
                    setState { pdfTool = pdfTool == .highlight ? .none : .highlight }
                },
                SizedBox(width: 4),
                _toolButton("Pen", active: pdfTool == .ink) { [self] in
                    setState { pdfTool = pdfTool == .ink ? .none : .ink }
                },
                SizedBox(width: 6),
                _barButton(pdfModified ? "Save •" : "Save") { [self] in
                    _savePdf()
                },
            ]
            return Row(children: items)
        }
        #endif
        return SizedBox(width: 0, height: 0)
    }

    /// A bar button with a toggled (accent) state.
    private func _toolButton(_ label: String, active: Bool,
                             onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: active ? Color(0x4D0A84FF) : pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Padding(
                    padding: EdgeInsets(horizontal: 11, vertical: 6),
                    child: Text(label, style: TextStyle(
                        color: active ? pal.accent : pal.controlText,
                        fontSize: 13))
                )
            )
        )
    }

    private func _barButton(_ label: String, onTap: @escaping () -> Void) -> Widget {
        return GestureDetector(
            onTap: onTap,
            behavior: .opaque,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: pal.control,
                    borderRadius: BorderRadius.all(Radius(circular: 6))
                ),
                child: Padding(
                    padding: EdgeInsets(horizontal: 11, vertical: 6),
                    child: Text(label, style: TextStyle(
                        color: pal.controlText, fontSize: 13))
                )
            )
        )
    }

    // MARK: - Canvas

    private func _canvasView() -> Widget {
        let canvas = _canvasSize()
        var isPdf = false
        let painter: CustomPainter
        #if os(Linux)
        if pdf != nil {
            isPdf = true
            let (rects, content) = _pdfLayout(canvas)
            let origin = _pdfContentOrigin(canvas, content)
            _updateCurrentPdfPage(rects: rects, origin: origin, canvas: canvas)
            _ensurePdfPages(canvas: canvas, rects: rects, origin: origin)
            var overlayRect: Rect? = nil
            var overlayPath: [Offset] = []
            if _annotPage != nil {
                if pdfTool == .highlight {
                    overlayRect = Rect.fromLTWH(
                        min(_annotStart.dx, _annotCurrent.dx),
                        min(_annotStart.dy, _annotCurrent.dy),
                        abs(_annotCurrent.dx - _annotStart.dx),
                        abs(_annotCurrent.dy - _annotStart.dy))
                } else if pdfTool == .ink {
                    overlayPath = _inkPoints
                }
            }
            painter = PdfDocPainter(
                pages: rects.enumerated().map { (i, rect) in
                    (rect: Rect.fromLTWH(origin.dx + rect.left,
                                         origin.dy + rect.top,
                                         rect.width, rect.height),
                     image: pdfImages[i])
                },
                background: pal.canvas,
                overlayRect: overlayRect,
                overlayPath: overlayPath)
        } else {
            painter = ImageCanvasPainter(image: image, dst: _imageRect(canvas),
                                         background: pal.canvas)
        }
        #else
        painter = ImageCanvasPainter(image: image, dst: _imageRect(canvas),
                                     background: pal.canvas)
        #endif
        _ = isPdf

        var stack: [Widget] = [
            Listener(
                onPointerDown: { [self] event in
                    viewerFocus.requestFocus()
                    guard event.buttons & 1 != 0 else { return }
                    #if os(Linux)
                    if pdf != nil, pdfTool != .none {
                        let (rects, content) = _pdfLayout(canvas)
                        let origin = _pdfContentOrigin(canvas, content)
                        if let hit = _pagePoint(at: event.localPosition,
                                                rects: rects, origin: origin) {
                            _annotPage = hit.page
                            _annotStart = event.localPosition
                            _annotCurrent = event.localPosition
                            _inkPoints = [event.localPosition]
                        }
                        return
                    }
                    // Interactive form fields: click checkboxes, focus
                    // text fields. Falls through to pan on empty areas.
                    if let pdf, pdf.hasForm {
                        let (rects, content) = _pdfLayout(canvas)
                        let origin = _pdfContentOrigin(canvas, content)
                        if let hit = _pagePoint(at: event.localPosition,
                                                rects: rects, origin: origin) {
                            let fieldType = pdf.formFieldType(page: hit.page,
                                                              x: hit.x, y: hit.y)
                            if fieldType > 0 {
                                // 2 checkbox, 3 radio: deterministic toggle
                                if fieldType == 2 || fieldType == 3 {
                                    pdf.formToggleCheck(page: hit.page,
                                                        x: hit.x, y: hit.y)
                                } else {
                                    pdf.formClick(page: hit.page,
                                                  x: hit.x, y: hit.y)
                                }
                                setState {
                                    // 4 combobox, 6 text field: keep focus
                                    // for typing; buttons commit instantly.
                                    _formFocusPage =
                                        (fieldType == 6 || fieldType == 4)
                                            ? hit.page : nil
                                    _invalidatePdfCaches(page: hit.page)
                                    pdfModified = true
                                    statusMessage = ""
                                }
                                return
                            } else if let focused = _formFocusPage {
                                pdf.killFormFocus()
                                setState {
                                    _formFocusPage = nil
                                    _invalidatePdfCaches(page: focused)
                                }
                            }
                        }
                    }
                    #endif
                    let now = Date().timeIntervalSince1970
                    if now - _lastClickAt < 0.4 {
                        // Double-click: toggle fit <-> 100%
                        setState {
                            if zoom == nil { _setZoom(1) }
                            else { zoom = nil; panX = 0; panY = 0 }
                        }
                        _lastClickAt = 0
                        return
                    }
                    _lastClickAt = now
                    _dragging = true
                    _lastDragPos = event.localPosition
                },
                onPointerMove: { [self] event in
                    #if os(Linux)
                    if _annotPage != nil, event.buttons & 1 != 0 {
                        setState {
                            _annotCurrent = event.localPosition
                            if pdfTool == .ink {
                                _inkPoints.append(event.localPosition)
                            }
                        }
                        return
                    }
                    #endif
                    guard _dragging, event.buttons & 1 != 0 else { return }
                    let dx = event.localPosition.dx - _lastDragPos.dx
                    let dy = event.localPosition.dy - _lastDragPos.dy
                    _lastDragPos = event.localPosition
                    setState { panX += dx; panY += dy }
                },
                onPointerUp: { [self] _ in
                    #if os(Linux)
                    if _annotPage != nil {
                        _finishAnnotation()
                        return
                    }
                    #endif
                    _dragging = false
                },
                onPointerSignal: { [self] event in
                    guard let scroll = event as? PointerScrollEvent else { return }
                    #if os(Linux)
                    // PDFs scroll like a document; Ctrl+wheel zooms.
                    if pdf != nil && !ctrlDown {
                        setState { panY -= scroll.scrollDelta.dy }
                        return
                    }
                    #endif
                    _zoomStep(scroll.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1)
                },
                behavior: .opaque,
                // CustomPaint does not clip: a zoomed image's dst rect goes
                // negative and would paint over the toolbar without this.
                child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius(circular: 0)),
                    child: CustomPaint(
                        painter: painter,
                        child: SizedBox(expand: ())
                    )
                )
            ),
        ]
        if image == nil && !isPdf && statusMessage.isEmpty {
            stack.append(Center(child: Text(
                "Open an image  (Ctrl+O)",
                style: TextStyle(color: pal.dimText, fontSize: 15))))
        }
        return Stack(children: stack)
    }

    // MARK: - File picker (open-only; same panel as the Text Editor's)

    private func _openPicker() {
        var dir = (path as NSString).deletingLastPathComponent
        var isDirObj: ObjCBool = false
        if path.isEmpty
            || !FileManager.default.fileExists(atPath: dir, isDirectory: &isDirObj)
            || !isDirObj.boolValue {
            dir = NSHomeDirectory()
        }
        setState {
            _pickerOpen = true
            _pickerEnter(dir)
        }
    }

    private func _pickerEnter(_ dir: String) {
        _pickerDir = dir
        _pickerScroll = 0
        _pickerEntries = Self._listDir(dir)
    }

    /// Directories plus image files only.
    private static func _listDir(_ path: String) -> [(name: String, isDir: Bool)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var out: [(name: String, isDir: Bool)] = []
        for name in names where !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path + "/" + name, isDirectory: &isDir)
            if isDir.boolValue
                || kOpenExts.contains((name as NSString).pathExtension.lowercased()) {
                out.append((name, isDir.boolValue))
            }
        }
        out.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.lowercased() < b.name.lowercased()
        }
        return out
    }

    private let _pickerRowH: Double = 26
    private let _pickerListH: Double = 300

    private func _pickerOverlay() -> Widget {
        return GestureDetector(
            onTap: { [self] in setState { _pickerOpen = false } },
            behavior: .opaque,
            child: ColoredBox(
                color: Color(0x66000000),
                child: Center(child: GestureDetector(
                    onTap: {},
                    behavior: .opaque,
                    child: _pickerPanel()
                ))
            )
        )
    }

    private func _pickerPanel() -> Widget {
        let rows: [Widget] = [
            Padding(
                padding: EdgeInsets(horizontal: 14, vertical: 10),
                child: Row(children: [
                    Text("Open Image", style: TextStyle(
                        color: pal.text, fontSize: 15, fontWeight: .w600)),
                    Expanded(child: SizedBox(height: 0)),
                    _barButton("Home") { [self] in
                        setState { _pickerEnter(NSHomeDirectory()) }
                    },
                    SizedBox(width: 6),
                    _barButton("Up") { [self] in
                        let parent = (_pickerDir as NSString).deletingLastPathComponent
                        setState { _pickerEnter(parent.isEmpty ? "/" : parent) }
                    },
                ])
            ),
            Padding(
                padding: EdgeInsets(left: 14, top: 0, right: 14, bottom: 8),
                child: Row(children: [Expanded(child:
                    Text(_pickerDir, style: TextStyle(color: pal.dimText,
                                                      fontSize: 11),
                         maxLines: 1))])
            ),
            SizedBox(height: 1, child: ColoredBox(color: pal.toolbarLine,
                                                  child: SizedBox(expand: ()))),
            _pickerList(),
            Padding(
                padding: EdgeInsets(left: 14, top: 10, right: 14, bottom: 12),
                child: Row(children: [
                    Expanded(child: SizedBox(height: 0)),
                    _barButton("Cancel") { [self] in
                        setState { _pickerOpen = false }
                    },
                ])
            ),
        ]

        return SizedBox(width: 540, child: DecoratedBox(
            decoration: BoxDecoration(
                color: pal.toolbar,
                borderRadius: BorderRadius.all(Radius(circular: 10)),
                boxShadow: [BoxShadow(color: Color(0x55000000),
                                      offset: Offset(0, 6),
                                      blurRadius: 24)]
            ),
            child: Column(mainAxisSize: .min, children: rows)
        ))
    }

    /// Windowed file list: renders only the visible rows; wheel scrolls.
    private func _pickerList() -> Widget {
        let count = _pickerEntries.count
        let maxScroll = max(0, Double(count) * _pickerRowH - _pickerListH)
        _pickerScroll = max(0, min(_pickerScroll, maxScroll))
        let first = Int(_pickerScroll / _pickerRowH)
        let visible = Int(_pickerListH / _pickerRowH) + 2
        let yShift = -(_pickerScroll - Double(first) * _pickerRowH)

        var rows: [Widget] = []
        if count == 0 {
            rows.append(Padding(
                padding: EdgeInsets(horizontal: 14, vertical: 10),
                child: Text("(no images here)", style: TextStyle(
                    color: pal.dimText, fontSize: 12))))
        } else {
            for i in first ..< min(count, first + visible) {
                rows.append(_pickerRow(_pickerEntries[i]))
            }
        }

        return SizedBox(height: _pickerListH, child: ClipRRect(
            borderRadius: BorderRadius.all(Radius(circular: 0)),
            child: Listener(
                onPointerSignal: { [self] event in
                    guard let scroll = event as? PointerScrollEvent else { return }
                    let target = max(0, min(_pickerScroll + scroll.scrollDelta.dy,
                                            maxScroll))
                    if target != _pickerScroll {
                        setState { _pickerScroll = target }
                    }
                },
                behavior: .opaque,
                child: Stack(children: [
                    Positioned(
                        left: 0, top: yShift, right: 0,
                        child: Column(mainAxisSize: .min, children: rows)
                    ),
                ])
            )
        ))
    }

    private func _pickerRow(_ entry: (name: String, isDir: Bool)) -> Widget {
        return GestureDetector(
            onTap: { [self] in
                let full = _pickerDir == "/" ? "/" + entry.name
                                             : _pickerDir + "/" + entry.name
                if entry.isDir {
                    setState { _pickerEnter(full) }
                } else {
                    setState { _pickerOpen = false }
                    _load(full)
                }
            },
            behavior: .opaque,
            child: SizedBox(height: _pickerRowH, child: Padding(
                padding: EdgeInsets(horizontal: 16, vertical: 0),
                child: Row(children: [
                    Expanded(child: Text(entry.name + (entry.isDir ? "/" : ""),
                        style: TextStyle(
                            color: entry.isDir ? pal.accent : pal.text,
                            fontSize: 13),
                        maxLines: 1)),
                ])
            ))
        )
    }
}
