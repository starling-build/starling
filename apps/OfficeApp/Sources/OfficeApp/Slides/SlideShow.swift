// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The slide show (S5): the deck's visible slides, one at a time,
// letterboxed on black and drawn by SlidePainter at full size, with the
// slide's transition played on the way in. PowerPoint's keys: → ↓ Space
// Return PageDown N and a click go on; ← ↑ Backspace PageUp P go back;
// Home and End; a number then Return jumps; B and W blank the screen; Esc
// ends. After the last slide comes PowerPoint's black end screen.

import Flutter
import FlutterSwiftBridge
import Foundation

final class SlideShowView: StatefulWidget {
    let deck: DeckController
    /// Pictures already decoded for the editor, shared rather than redone.
    let images: SlideTextCache
    /// Index into `deck.slides` to start at.
    let start: Int
    /// Presenter view: the slide beside the next one, the notes, a timer.
    let presenter: Bool
    let onEnd: () -> Void

    init(deck: DeckController, images: SlideTextCache, start: Int, presenter: Bool = false,
         onEnd: @escaping () -> Void) {
        self.deck = deck
        self.images = images
        self.start = start
        self.presenter = presenter
        self.onEnd = onEnd
        super.init()
    }

    override func createState() -> State<StatefulWidget> { SlideShowState() }
}

final class SlideShowState: State<StatefulWidget>, TickerProvider {
    private var _order: [Int] = []
    /// Position in `_order`; `_order.count` is the end screen.
    private var _at = 0
    private var _from: Int? = nil
    private var _controller: AnimationController!
    private var _blank: Color? = nil
    private var _digits = ""
    private let _focus = FocusNode(debugLabel: "slide show")
    private let _chords = KeyChordTracker()
    /// Text laid out at show size: a cache of its own, so the thumbnails'
    /// and the show's layouts do not evict each other.
    private var _cache: SlideTextCache!
    private var _cursorGeneration = 0
    /// The editor's repaint-on-decode, restored when the show ends.
    private var _sourceDecoded: (() -> Void)?
    /// The current slide's animations: groups played so far, and the one
    /// playing (its progress is `_build`'s value over the group's length).
    private var _plan = AnimationPlan([])
    private var _played = 0
    private var _playing = false
    private var _build: AnimationController!
    /// Presenter view's timer: time banked before the last start, and when
    /// it last started (nil while paused).
    private var _timerBanked = 0.0
    private var _timerSince: Date? = Date()
    private var _clockGeneration = 0

    private var _w: SlideShowView { widget as! SlideShowView }

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker { Ticker(onTick) }

    override func initState() {
        super.initState()
        let deck = _w.deck
        _order = deck.slides.indices.filter { !deck.slides[$0].hidden }
        if _order.isEmpty { _order = Array(deck.slides.indices) }
        // Starting on a hidden slide shows it anyway, as PowerPoint does.
        if let i = _order.firstIndex(of: _w.start) { _at = i } else {
            _order.insert(_w.start, at: _order.firstIndex { $0 > _w.start } ?? _order.count)
            _at = _order.firstIndex(of: _w.start) ?? 0
        }
        _cache = SlideTextCache(images: _w.images)
        // Pictures decode in the editor's cache: repaint the show when one
        // lands there too.
        _sourceDecoded = _w.images.onImageDecoded
        _w.images.onImageDecoded = { [weak self, previous = _sourceDecoded] in
            previous?()
            if let self, self.mounted { self.setState {} }
        }
        _controller = AnimationController(duration: .milliseconds(500), vsync: self)
        _controller.value = 1
        _controller.addListener({ [weak self] in self?.setState {} }, owner: self)
        _build = AnimationController(duration: .milliseconds(500), vsync: self)
        _build.addListener({ [weak self] in self?.setState {} }, owner: self)
        _build.addStatusListener({ [weak self] status in
            guard let self, status == .completed, self._playing else { return }
            self.setState {
                self._playing = false
                self._played += 1
            }
        })
        _enterSlide(forward: true)
        _focus.onKeyData = { [weak self] key in self?._key(key) ?? false }
        _focus.requestFocus()
        if _w.presenter { _tickClock() } else { _hideCursorSoon() }
    }

    override func dispose() {
        _controller.removeListeners(owner: self)
        _controller.dispose()
        _build.removeListeners(owner: self)
        _build.dispose()
        _focus.dispose()
        _w.images.onImageDecoded = _sourceDecoded
        hostSetMouseCursor?("basic")
        super.dispose()
    }

    // MARK: Moving

    /// A new slide's animations: from the start going forward (playing a
    /// first group that starts by itself), all played coming back.
    private func _enterSlide(forward: Bool) {
        _build.stop()
        _playing = false
        _plan = _at < _order.count ? AnimationPlan(_w.deck.slides[_order[_at]].animations) : AnimationPlan([])
        _played = forward ? 0 : _plan.groups.count
        if forward && _plan.autoStart { _playGroup() }
    }

    private func _playGroup() {
        guard _played < _plan.groups.count else { return }
        let length = _plan.length(_played)
        guard length > 0 else { _played += 1; return }
        _playing = true
        _build.duration = .milliseconds(Int(length * 1000))
        _build.value = 0
        _build.forward()
    }

    /// `back`: stepping back a slide, which arrives with its animations
    /// all played; any other move starts the slide from the beginning.
    private func _go(to target: Int, animate: Bool, back: Bool = false) {
        let t = max(0, min(_order.count, target))
        guard t != _at else { return }
        _blank = nil
        let transition = t < _order.count ? _w.deck.slides[_order[t]].transition : SlideTransition()
        if animate, transition.kind != .none, _at < _order.count {
            _from = _at
            _controller.duration = .milliseconds(Int(transition.duration * 1000))
            _controller.value = 0
            _controller.forward()
        } else {
            _from = nil
            _controller.value = 1
        }
        setState {
            _at = t
            _enterSlide(forward: !back)
        }
    }

    private func _next() {
        if _at >= _order.count { _w.onEnd(); return }
        // A transition still running finishes at once on the next press;
        // so does a group of animations.
        if _controller.value < 1 { _controller.value = 1; return }
        if _playing {
            _build.stop()
            setState { _playing = false; _played += 1 }
            return
        }
        if _played < _plan.groups.count {
            setState { _playGroup() }
            return
        }
        _go(to: _at + 1, animate: true)
    }

    private func _previous() {
        if _at < _order.count, _played > 0 || _playing {
            _build.stop()
            setState {
                if !_playing { _played -= 1 }
                _playing = false
            }
            return
        }
        _go(to: _at - 1, animate: false, back: true)
    }

    // MARK: Input

    private func _key(_ key: KeyData) -> Bool {
        if _chords.track(key) { return false }
        guard key.type == .down || key.type == .repeat else { return true }
        let named = KeyChordTracker.named(key.logical)
        if let letter = KeyChordTracker.letter(key.logical), !_chords.primary {
            switch letter {
            case "b": setState { _blank = _blank == nil ? Color(0xFF000000) : nil }; return true
            case "w": setState { _blank = _blank == nil ? Color(0xFFFFFFFF) : nil }; return true
            case "n": _next(); return true
            case "p": _previous(); return true
            default: break
            }
        }
        if key.logical >= 0x30 && key.logical <= 0x39 {
            _digits.append(Character(UnicodeScalar(UInt8(key.logical))))
            return true
        }
        switch named {
        case .escape: _w.onEnd()
        case .enter:
            if let n = Int(_digits), n >= 1 {
                _digits = ""
                if let at = _order.firstIndex(of: n - 1) { _go(to: at, animate: false) }
            } else {
                _next()
            }
        case .right, .down, .pageDown: _next()
        case .left, .up, .pageUp, .backspace: _previous()
        case .home: _go(to: 0, animate: false)
        case .end: _go(to: _order.count - 1, animate: false)
        default:
            if key.logical == 0x20 { _next() }
        }
        _digits = named == .enter ? "" : _digits
        return true
    }

    /// The pointer hides after two seconds still, as in PowerPoint's show.
    private func _hideCursorSoon() {
        _cursorGeneration += 1
        let gen = _cursorGeneration
        hostSetMouseCursor?("basic")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.mounted, self._cursorGeneration == gen else { return }
            hostSetMouseCursor?("none")
        }
    }

    // MARK: Presenter view

    /// Redraw once a second for the timer and the clock.
    private func _tickClock() {
        _clockGeneration += 1
        let gen = _clockGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.mounted, self._clockGeneration == gen else { return }
            self.setState {}
            self._tickClock()
        }
    }

    private var _elapsed: Double {
        _timerBanked + (_timerSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func _presenterView(_ context: any BuildContext, show: Widget) -> Widget {
        let deck = _w.deck
        let white = Color(0xFFF2F2F2), dim = Color(0xFFA8A8A8)
        let font = OfficeFonts.sans
        func label(_ s: String, _ size: Double, _ color: Color) -> Widget {
            Text(s, style: Flutter.TextStyle(color: color, fontSize: size, fontFamily: font))
        }
        let nextIndex = _at + 1 < _order.count ? _order[_at + 1] : nil
        let next: Widget = nextIndex.map { i in
            AspectRatio(aspectRatio: deck.slideSize.width / deck.slideSize.height, child: CustomPaint(
                painter: SlidePainter(slide: deck.slides[i], theme: deck.theme, slideSize: deck.slideSize,
                                      revision: deck.revision, cache: _cache),
                child: SizedBox(expand: ())))
        } ?? label("End of slide show", 16, dim)
        let remaining = _at < _order.count ? max(0, _plan.groups.count - _played) : 0
        let notes = _at < _order.count ? deck.slides[_order[_at]].notes.document.plainText() : ""
        let t = Int(_elapsed)
        let timer = String(printf: "%d:%02d:%02d", Int32(t / 3600), Int32((t / 60) % 60), Int32(t % 60))
        let clock = SlidesDates.format(Date(), "h:mm a")
        func button(_ text: String, _ action: @escaping () -> Void) -> Widget {
            Button(onPressed: action, child: Text(text))
        }
        let counter = _at < _order.count ? "Slide \(_order[_at] + 1) of \(deck.slides.count)" : "End of show"
        let bar = Padding(padding: EdgeInsets(left: 20, top: 10, right: 20, bottom: 10), child: Row(children: [
            label(timer, 26, white),
            SizedBox(width: 12, height: nil, child: nil),
            button(_timerSince == nil ? "Resume" : "Pause") { [weak self] in
                guard let self else { return }
                self.setState {
                    if let since = self._timerSince {
                        self._timerBanked += Date().timeIntervalSince(since)
                        self._timerSince = nil
                    } else {
                        self._timerSince = Date()
                    }
                }
            },
            SizedBox(width: 6, height: nil, child: nil),
            button("Reset") { [weak self] in
                guard let self else { return }
                self.setState {
                    self._timerBanked = 0
                    if self._timerSince != nil { self._timerSince = Date() }
                }
            },
            Expanded(child: Center(child: label(counter, 18, white))),
            label(clock, 22, white),
            SizedBox(width: 16, height: nil, child: nil),
            button("End Show") { [weak self] in self?._w.onEnd() },
        ]))
        let controls = Padding(padding: EdgeInsets(left: 0, top: 10, right: 0, bottom: 0), child: Row(
            mainAxisAlignment: .center, children: [
                button("◀  Back") { [weak self] in self?._previous() },
                SizedBox(width: 12, height: nil, child: nil),
                button(remaining > 0 ? "Next animation  ▶" : "Next slide  ▶") { [weak self] in self?._next() },
            ]))
        return ColoredBox(color: Color(0xFF1B1B1B), child: Column(crossAxisAlignment: .stretch, children: [
            Expanded(child: Padding(padding: EdgeInsets(left: 20, top: 20, right: 20, bottom: 0), child: Row(
                crossAxisAlignment: .stretch, children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: .stretch, children: [
                        label("Current slide", 13, dim),
                        SizedBox(width: nil, height: 6, child: nil),
                        Expanded(child: show),
                        controls,
                    ])),
                    SizedBox(width: 24, height: nil, child: nil),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: .stretch, children: [
                        label(remaining > 0 ? "Next slide (after \(remaining) more animation\(remaining == 1 ? "" : "s") here)" : "Next slide", 13, dim),
                        SizedBox(width: nil, height: 6, child: nil),
                        next,
                        SizedBox(width: nil, height: 20, child: nil),
                        label("Notes", 13, dim),
                        SizedBox(width: nil, height: 6, child: nil),
                        Expanded(child: SingleChildScrollView(child: Text(
                            notes.isEmpty ? "No notes for this slide." : notes,
                            style: Flutter.TextStyle(color: notes.isEmpty ? dim : white, fontSize: 22, height: 1.35, fontFamily: font)))),
                    ])),
                ]))),
            bar,
        ]))
    }

    // MARK: Build

    override func build(_ context: any BuildContext) -> Widget {
        let deck = _w.deck
        let current: Slide? = _at < _order.count ? deck.slides[_order[_at]] : nil
        let previous: Slide? = _from.flatMap { $0 < _order.count ? deck.slides[_order[$0]] : nil }
        let progress = _controller.value
        let elapsed = _playing ? _build.value * _plan.length(_played) : nil
        let reveals = _plan.reveals(played: _played, elapsed: elapsed)
        let show = Listener(
            onPointerDown: { [weak self] e in
                guard let self else { return }
                self._focus.requestFocus()
                if e.buttons & kSecondaryMouseButton != 0 { self._previous() } else { self._next() }
            },
            onPointerHover: { [weak self] _ in
                guard let self, !self._w.presenter else { return }
                self._hideCursorSoon()
            },
            behavior: .opaque,
            child: CustomPaint(
                painter: _ShowPainter(current: current, previous: progress < 1 ? previous : nil,
                                      progress: progress, theme: deck.theme, slideSize: deck.slideSize,
                                      cache: _cache, blank: _blank, reveals: reveals,
                                      revision: deck.revision &+ Int(progress * 1000) &+ (_blank == nil ? 0 : 7) &+ _at * 10007
                                          &+ _played * 131 &+ Int((elapsed ?? -1) * 1000) * 7919),
                child: SizedBox(expand: ())))
        return _w.presenter ? _presenterView(context, show: show) : show
    }
}

extension SlideTextCache {
    /// A cache with its own text layouts that borrows `images`' decoded
    /// pictures.
    convenience init(images: SlideTextCache) {
        self.init()
        imageSource = images
    }
}

/// One frame of the show: black, the slide letterboxed, and during a
/// transition the outgoing slide under (or beside) the incoming one.
private final class _ShowPainter: CustomPainter {
    let current: Slide?
    let previous: Slide?
    let progress: Double
    let theme: DeckTheme
    let slideSize: Size
    let cache: SlideTextCache
    let blank: Color?
    let reveals: ShapeReveals
    let revision: Int

    init(current: Slide?, previous: Slide?, progress: Double, theme: DeckTheme, slideSize: Size,
         cache: SlideTextCache, blank: Color?, reveals: ShapeReveals, revision: Int) {
        self.current = current
        self.previous = previous
        self.progress = progress
        self.theme = theme
        self.slideSize = slideSize
        self.cache = cache
        self.blank = blank
        self.reveals = reveals
        self.revision = revision
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let black = Paint()
        black.style = .fill
        black.color = blank ?? Color(0xFF000000)
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), black)
        if blank != nil { return }
        let scale = min(size.width / slideSize.width, size.height / slideSize.height)
        let w = (slideSize.width * scale).rounded(), h = (slideSize.height * scale).rounded()
        let box = Rect.fromLTWH(((size.width - w) / 2).rounded(), ((size.height - h) / 2).rounded(), w, h)
        guard let current else {
            let tp = TextPainter(text: TextSpan(text: "End of slide show, click to exit.", style: Flutter.TextStyle(
                color: Color(0xFFBBBBBB), fontSize: 18, fontFamily: OfficeFonts.sans)), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: size.width)
            tp.paint(canvas, Offset(24, 24))
            tp.dispose()
            return
        }
        func draw(_ slide: Slide, at offset: Offset) {
            canvas.save()
            canvas.translate(box.left + offset.dx, box.top + offset.dy)
            // The outgoing slide as its animations left it: all played.
            SlidePainter(slide: slide, theme: theme, slideSize: slideSize, revision: 0, cache: cache,
                         reveals: slide === current ? reveals : ShapeReveals())
                .paint(canvas, Size(w, h))
            canvas.restore()
        }
        canvas.save()
        canvas.clipRect(box)
        guard let previous, progress < 1 else {
            draw(current, at: .zero)
            canvas.restore()
            return
        }
        let t = progress
        let kind = current.transition.raw != nil ? .fade : current.transition.kind
        // PresentationML's dir names where the motion heads: "l" moves the
        // picture leftwards, so the new slide enters from the right.
        let (dx, dy): (Double, Double) = {
            switch current.transition.direction {
            case .left: return (w, 0)
            case .right: return (-w, 0)
            case .up: return (0, h)
            case .down: return (0, -h)
            }
        }()
        switch kind {
        case .push:
            draw(previous, at: Offset(-dx * t, -dy * t))
            draw(current, at: Offset(dx * (1 - t), dy * (1 - t)))
        case .cover:
            draw(previous, at: .zero)
            draw(current, at: Offset(dx * (1 - t), dy * (1 - t)))
        case .wipe:
            draw(previous, at: .zero)
            let reveal: Rect
            switch current.transition.direction {
            case .left: reveal = Rect.fromLTRB(box.right - w * t, box.top, box.right, box.bottom)
            case .right: reveal = Rect.fromLTRB(box.left, box.top, box.left + w * t, box.bottom)
            case .up: reveal = Rect.fromLTRB(box.left, box.bottom - h * t, box.right, box.bottom)
            case .down: reveal = Rect.fromLTRB(box.left, box.top, box.right, box.top + h * t)
            }
            canvas.save()
            canvas.clipRect(reveal)
            draw(current, at: .zero)
            canvas.restore()
        default:
            draw(previous, at: .zero)
            let fade = Paint()
            fade.color = Color(Int((t * 255).rounded()) << 24)
            canvas.saveLayer(box, fade)
            draw(current, at: .zero)
            canvas.restore()
        }
        canvas.restore()
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? _ShowPainter else { return true }
        return old.revision != revision || old.current !== current || old.previous !== previous
    }
}
