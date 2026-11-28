// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The slide show (S5): the deck's visible slides, one at a time,
// letterboxed on black and drawn by SlidePainter at full size, with the
// slide's transition played on the way in. PowerPoint's keys: → ↓ Space
// Return PageDown N and a click go on; ← ↑ Backspace PageUp P go back;
// Home and End; a number then Return jumps; B and W blank the screen; Esc
// ends. After the last slide comes PowerPoint's black end screen.

import Flutter
import OfficeText
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
    /// Rehearse Timings: the show times each slide and offers to keep the times.
    let rehearse: Bool
    let onEnd: () -> Void
    let landing: Bool
    let onSlideChanged: ((Int) -> Void)?

    init(deck: DeckController, images: SlideTextCache, start: Int, presenter: Bool = false, rehearse: Bool = false,
         onEnd: @escaping () -> Void, key: (any Key)? = nil, landing: Bool = false,
         onSlideChanged: ((Int) -> Void)? = nil) {
        self.deck = deck
        self.images = images
        self.start = start
        self.presenter = presenter
        self.rehearse = rehearse
        self.onEnd = onEnd
        self.landing = landing
        self.onSlideChanged = onSlideChanged
        super.init(key: key)
    }

    override func createState() -> State<StatefulWidget> { SlideShowState() }
}

final class SlideShowState: State<StatefulWidget>, TickerProvider {
    private var _order: [Int] = []
    /// Position in `_order`; `_order.count` is the end screen.
    private(set) var _at = 0
    private var _from: Int? = nil
    private var _controller: AnimationController!
    private var _blank: Color? = nil
    private var _digits = ""
    private var _pointerStart: Offset?
    /// A finger on the show (iPad): where it landed, the press-and-hold that raises the controls, and whether they are up.
    /// A finger has no Escape, no right button and no arrow keys, so the controls are how it goes back and ends the show.
    private let _touch = TouchMenuTrigger()
    private var _touchStart: Offset?
    private(set) var _controlsShown = false
    private var _controlsOpenedByThisTouch = false
    private var _controlsGeneration = 0
    private var _assetRevision = 0
    private let _focus = FocusNode(debugLabel: "slide show")
    private let _chords = KeyChordTracker()
    /// Text laid out at show size: a cache of its own, so the thumbnails'
    /// and the show's layouts do not evict each other.
    private var _cache: SlideTextCache!
    private var _cursorGeneration = 0
    private var _advanceGeneration = 0
    /// Presenter view: the notes' type size, and whether the grid of every slide is open.
    private(set) var _notesSize = 22.0
    private(set) var _seeAll = false
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
    /// Rehearse Timings: seconds spent on each slide (by deck index), the running slide's clock, and the keep-the-times question.
    private(set) var _rehearsed: [Int: Double] = [:]
    private var _slideBanked = 0.0
    private var _slideSince: Date? = Date()
    private(set) var _asking = false
    /// Clips playing or paused on the current slide, by shape id, and the
    /// video frame last decoded for each. Poster drawing never depends on these.
    private var _players: [Int: MediaPlayer] = [:]
    private var _videoFrames: [Int: Image] = [:]
    private var _mediaGeneration = 0
    private var _decoding: Set<Int> = []
    private var _frameSerial = 0

    private var _w: SlideShowView { widget as! SlideShowView }

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker { Ticker(onTick) }

    override func initState() {
        super.initState()
        bind(_focus)
        let deck = _w.deck
        _order = _w.landing ? deck.slides.indices.filter { !deck.slides[$0].hidden } : deck.showOrder()
        if _order.isEmpty { _order = Array(deck.slides.indices) }
        // Starting on a hidden slide shows it anyway, as PowerPoint does.
        if let i = _order.firstIndex(of: _w.start) { _at = i } else {
            _order.insert(_w.start, at: _order.firstIndex { $0 > _w.start } ?? _order.count)
            _at = _order.firstIndex(of: _w.start) ?? 0
        }
        _cache = SlideTextCache(images: _w.images)
        SystemFontsNotifier.shared.addListener({ [weak self] in
            guard let self else { return }
            self._cache = SlideTextCache(images: self._w.images)
            if self.mounted { self.setState { self._assetRevision &+= 1 } }
        }, owner: self)
        // Pictures decode in the editor's cache: repaint the show when one
        // lands there too.
        _sourceDecoded = _w.images.onImageDecoded
        _w.images.onImageDecoded = { [weak self, previous = _sourceDecoded] in
            previous?()
            if let self, self.mounted { self.setState { self._assetRevision &+= 1 } }
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
        if _w.presenter || _w.rehearse { _tickClock() }
        if !_w.presenter { _hideCursorSoon() }
    }

    override func dispose() {
        _stopMedia()
        SystemFontsNotifier.shared.removeListeners(owner: self)
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

    func showSlide(_ index: Int) { _go(to: index, animate: false) }

    /// A new slide's animations: from the start going forward (playing a
    /// first group that starts by itself), all played coming back.
    private func _enterSlide(forward: Bool) {
        _build.stop()
        _playing = false
        _plan = _at < _order.count ? AnimationPlan(_w.deck.slides[_order[_at]].animations) : AnimationPlan([])
        _played = forward ? 0 : _plan.groups.count
        if forward && _plan.autoStart { _playGroup() }
        _scheduleAutoAdvance()
    }

    /// Advance Slide "After": the show moves on by itself this many seconds after the slide arrives,
    /// once its animations have finished.
    private func _scheduleAutoAdvance() {
        _advanceGeneration += 1
        guard _at < _order.count, !_w.landing, !_w.rehearse, _w.deck.show.useTimings || _w.deck.show.kind == .kiosk,
              let after = _w.deck.slides[_order[_at]].transition.advanceAfter else { return }
        let gen = _advanceGeneration
        func fire(_ wait: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self, self.mounted, self._advanceGeneration == gen else { return }
                if self._playing || self._controller.value < 1 { fire(0.25); return }
                self._go(to: self._at + 1, animate: true)
            }
        }
        fire(after)
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
        _stopMedia()
        // Loop continuously until Esc: past the last slide is the first again (kiosk always loops).
        let loops = !_w.landing && !_w.rehearse && (_w.deck.show.loop || _w.deck.show.kind == .kiosk) && !_order.isEmpty
        let t = _w.landing ? max(0, min(_order.count - 1, target))
            : (loops && target >= _order.count) ? 0 : max(0, min(_order.count, target))
        guard t != _at else { return }
        _bankSlideTime()
        if _w.rehearse, t >= _order.count { _asking = true }
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
        _w.onSlideChanged?(t)
    }

    /// What a finger's travel from `start` to `end` does in the show: a tap goes on as a click does, a swipe to the left goes
    /// on, a swipe to the right goes back, and anything between (a slow drift) does nothing.
    enum TouchStep: Equatable { case tap, next, previous, none }
    static func touchStep(from start: Offset, to end: Offset) -> TouchStep {
        let dx = end.dx - start.dx, dy = end.dy - start.dy
        if abs(dx) > 40 && abs(dx) > abs(dy) { return dx > 0 ? .previous : .next }
        return abs(dx) < 12 && abs(dy) < 12 ? .tap : .none
    }

    /// The controls a finger raises by holding (Back, End Show, Next), put away again after a few seconds or by a touch elsewhere.
    /// `fromHold`: raised by the finger that is still down, whose lifting must not also count as a tap.
    private func _showControls(fromHold: Bool) {
        guard !_w.landing, !_w.presenter else { return }
        if fromHold { _controlsOpenedByThisTouch = true }
        setState { _controlsShown = true }
        _controlsGeneration += 1
        let gen = _controlsGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.mounted, self._controlsGeneration == gen else { return }
            self.setState { self._controlsShown = false }
        }
    }

    private func _hideControls() {
        _controlsGeneration += 1
        setState { _controlsShown = false }
    }

    private func _touchControls(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func gap() -> Widget { SizedBox(width: 8, height: nil, child: nil) }
        func pill(_ text: String, _ action: @escaping () -> Void) -> Widget {
            SizedBox(width: nil, height: 44, child: Button(onPressed: action, child: Text(text)))
        }
        return Positioned(left: 0, top: nil, right: 0, bottom: 28, child: Center(child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(10)),
            child: Padding(padding: EdgeInsets(left: 10, top: 8, right: 10, bottom: 8), child: Row(mainAxisSize: .min, children: [
                pill("Back") { [weak self] in self?._previous(); self?._showControls(fromHold: false) },
                gap(),
                pill("End Show") { [weak self] in self?._w.onEnd() },
                gap(),
                pill("Next") { [weak self] in self?._next(); self?._showControls(fromHold: false) },
            ])))))
    }

    /// A press that is not a swipe: a link or a clip under it takes it, otherwise it goes on a step (a right button goes back).
    private func _press(at position: Offset, secondary: Bool, context: any BuildContext) {
        if !secondary, let box = context.findRenderObject() as? RenderBox,
           let l = _link(at: box.globalToLocal(position), size: box.size), _follow(l) { return }
        if !secondary, let box = context.findRenderObject() as? RenderBox,
           let clip = _clip(at: box.globalToLocal(position), size: box.size) { _toggleMedia(clip); return }
        if _w.landing { _pointerStart = position }
        else if secondary { _previous() } else { _next(click: true) }
    }

    /// `click`: a mouse click, which a slide set not to advance on a click ignores (keys still move on).
    func _pressNext(click: Bool = false) { setState {}; _next(click: click) }

    private func _next(click: Bool = false) {
        if _at >= _order.count { _w.rehearse ? _finishRehearsal() : _w.onEnd(); return }
        if click, _w.deck.show.kind == .kiosk { return }
        if click, !_w.deck.slides[_order[_at]].transition.advanceOnClick { return }
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

    // MARK: Media

    /// The clip under a click, if any (clips inserted in this editor: a file's own are kept opaque).
    private func _clip(at p: Offset, size: Size) -> SlideShape? {
        guard _at < _order.count else { return nil }
        let deck = _w.deck, slide = deck.slides[_order[_at]]
        let k = min(size.width / deck.slideSize.width, size.height / deck.slideSize.height)
        let w = (deck.slideSize.width * k).rounded(), h = (deck.slideSize.height * k).rounded()
        let pt = Offset((p.dx - ((size.width - w) / 2).rounded()) / k, (p.dy - ((size.height - h) / 2).rounded()) / k)
        return slide.shapes.reversed().first { $0.media != nil && !$0.invisible && $0.frame.contains(pt) }
    }

    /// A click on a clip: first click plays it, the next pauses, then resumes.
    private func _toggleMedia(_ shape: SlideShape) {
        guard let clip = shape.media else { return }
        if let player = _players[shape.id] {
            if player.status == .playing || player.status == .loading { player.pause() } else { player.play() }
            setState {}
            return
        }
        #if !os(WASI)
        guard let player = makeMediaPlayer() else { return }
        #if os(iOS)
        // (An app has no home directory to cache in: the sandbox's temporary folder holds the clip while it plays.)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("starling-office-media")
        #else
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/starling-office/media")
        #endif
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("clip-\(shape.id).\(clip.fileExtension)")
        guard (try? clip.data.write(to: file)) != nil else { return }
        _players[shape.id] = player
        player.open(url: file.absoluteString)
        _pollMedia()
        #endif
    }

    private func _stopMedia() {
        _mediaGeneration += 1
        for (_, p) in _players { p.stop() }
        _players = [:]
        _videoFrames = [:]
        _decoding = []
    }

    /// Pulls due frames about thirty times a second while a clip is open.
    private func _pollMedia() {
        _mediaGeneration += 1
        let gen = _mediaGeneration
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.033) { [weak self] in
                guard let self, self.mounted, self._mediaGeneration == gen, !self._players.isEmpty else { return }
                for (id, player) in self._players {
                    guard let f = player.pollFrame(), !self._decoding.contains(id) else { continue }
                    self._decoding.insert(id)
                    decodeImageFromPixels(f.pixels, width: f.width, height: f.height, format: .rgba8888, callback: { [weak self] image in
                        DispatchQueue.main.async {
                            guard let self, self.mounted, self._mediaGeneration == gen else { return }
                            self._decoding.remove(id)
                            self.setState { self._videoFrames[id] = image; self._frameSerial &+= 1 }
                        }
                    })
                }
                tick()
            }
        }
        tick()
    }

    // MARK: Links

    /// The link under a click: the shape's own, else the one on the text run there.
    private func _link(at p: Offset, size: Size) -> String? {
        guard _at < _order.count else { return nil }
        let deck = _w.deck, slide = deck.slides[_order[_at]]
        let k = min(size.width / deck.slideSize.width, size.height / deck.slideSize.height)
        let w = (deck.slideSize.width * k).rounded(), h = (deck.slideSize.height * k).rounded()
        let left = ((size.width - w) / 2).rounded(), top = ((size.height - h) / 2).rounded()
        let pt = Offset((p.dx - left) / k, (p.dy - top) / k)
        guard pt.dx >= 0, pt.dy >= 0, pt.dx <= deck.slideSize.width, pt.dy <= deck.slideSize.height else { return nil }
        for shape in slide.shapes.reversed() where !shape.invisible {
            var q = pt
            if shape.rotation != 0 {
                let c = shape.frame.center, a = -shape.rotation * .pi / 180
                let dx = pt.dx - c.dx, dy = pt.dy - c.dy
                q = Offset(c.dx + dx * cos(a) - dy * sin(a), c.dy + dx * sin(a) + dy * cos(a))
            }
            guard shape.frame.contains(q) else { continue }
            if let l = shape.link, !l.isEmpty { return l }
            guard let text = shape.text, let layout = _cache.layout(shape, pxPerPt: 1) else { continue }
            let lp = Offset(q.dx - shape.frame.left - shape.drawInsets.left, q.dy - shape.frame.top - _cache.textTop(shape, pxPerPt: 1))
            let pos = layout.position(at: lp, text.document)
            let para = text.document.paragraphs[pos.paragraph]
            guard !para.text.isEmpty else { continue }
            let l = para.style(at: min(pos.offset, para.text.count - 1)).link
            if let l, !l.isEmpty { return l }
        }
        return nil
    }

    /// Follows a link; false when it is not one the show acts on (the click then advances).
    private func _follow(_ link: String) -> Bool {
        let deck = _w.deck
        func show(_ slideIndex: Int) {
            if !_order.contains(slideIndex) { _order.insert(slideIndex, at: min(_at + 1, _order.count)); _go(to: _at + 1, animate: false); return }
            _go(to: _order.firstIndex(of: slideIndex)!, animate: false)
        }
        if link.hasPrefix("slide:") {
            let key = String(link.dropFirst(6))
            guard let i = deck.slides.firstIndex(where: { ($0.sourcePart ?? "new:\($0.id)") == key }) else { return false }
            show(i); return true
        }
        if link.hasPrefix("action:") {
            let a = link.dropFirst(7)
            if a.hasSuffix("jump=nextslide") { _go(to: _at + 1, animate: true) }
            else if a.hasSuffix("jump=previousslide") { _go(to: _at - 1, animate: false, back: true) }
            else if a.hasSuffix("jump=firstslide") { _go(to: 0, animate: false) }
            else if a.hasSuffix("jump=lastslide") { _go(to: max(0, _order.count - 1), animate: false) }
            else if a.hasSuffix("jump=endshow") { _w.onEnd() }
            else { return false }
            return true
        }
        let lower = link.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:") else { return false }
        hostOpenURL?(link)
        return true
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
        case .escape: _w.rehearse ? _finishRehearsal() : _w.onEnd()
        case _ where !_w.landing && _w.deck.show.kind == .kiosk: break   // a kiosk answers to Esc alone
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
        if _w.landing { return }
        _cursorGeneration += 1
        let gen = _cursorGeneration
        hostSetMouseCursor?("basic")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.mounted, self._cursorGeneration == gen else { return }
            hostSetMouseCursor?("none")
        }
    }

    // MARK: Rehearse Timings

    private var _slideElapsed: Double { _slideBanked + (_slideSince.map { Date().timeIntervalSince($0) } ?? 0) }
    private var _rehearsedTotal: Double {
        let leaving = _at < _order.count ? _order[_at] : -1
        return _rehearsed.filter { $0.key != leaving }.values.reduce(0, +) + (leaving >= 0 ? _slideElapsed : 0)
    }

    /// The slide being left keeps the time it was on screen; the next one starts at zero.
    private func _bankSlideTime() {
        guard _w.rehearse else { return }
        if _at < _order.count { _rehearsed[_order[_at]] = _slideElapsed }
        _slideBanked = 0
        _slideSince = Date()
    }

    private func _finishRehearsal() {
        guard !_asking else { return }
        _bankSlideTime()
        setState { _asking = true }
    }

    func keepRehearsedTimes(_ keep: Bool) {
        if keep { _w.deck.applyRehearsal(_rehearsed) }
        _w.onEnd()
    }

    private func _rehearseBar(_ context: any BuildContext) -> Widget {
        let fluent = FluentTheme.of(context)
        func clock(_ t: Double) -> String {
            let n = Int(t)
            return n >= 3600 ? "\(n / 3600):\(n % 3600 / 60 < 10 ? "0" : "")\(n % 3600 / 60):\(n % 60 < 10 ? "0" : "")\(n % 60)"
                : "\(n / 60):\(n % 60 < 10 ? "0" : "")\(n % 60)"
        }
        func gap() -> Widget { SizedBox(width: 8, height: nil, child: nil) }
        if _asking {
            return Center(child: DecoratedBox(
                decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                          border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                          borderRadius: BorderRadius.circular(8)),
                child: Padding(padding: EdgeInsets(all: 24), child: Column(mainAxisSize: .min, crossAxisAlignment: .start, children: [
                    Text("The slide show lasted \(clock(_rehearsed.values.reduce(0, +))).", style: fluent.typography.bodyStrong),
                    SizedBox(width: nil, height: 6, child: nil),
                    Text("Do you want to keep the new slide timings?"),
                    SizedBox(width: nil, height: 16, child: nil),
                    Row(mainAxisSize: .min, children: [
                        FilledButton(onPressed: { [weak self] in self?.keepRehearsedTimes(true) }, child: Text("Yes")),
                        gap(),
                        Button(onPressed: { [weak self] in self?.keepRehearsedTimes(false) }, child: Text("No")),
                    ]),
                ]))))
        }
        let paused = _slideSince == nil
        return Positioned(left: 12, top: 12, right: nil, bottom: nil, child: DecoratedBox(
            decoration: BoxDecoration(color: OfficeAppearance.surface(fluent),
                                      border: Border.all(color: fluent.resources.controlStrokeColorDefault, width: 1),
                                      borderRadius: BorderRadius.circular(6)),
            child: Padding(padding: EdgeInsets(left: 10, top: 6, right: 10, bottom: 6), child: Row(mainAxisSize: .min, children: [
                Button(onPressed: { [weak self] in self?._next() }, child: Text("Next")),
                gap(),
                Button(onPressed: { [weak self] in
                    guard let self else { return }
                    self.setState {
                        if let since = self._slideSince { self._slideBanked += Date().timeIntervalSince(since); self._slideSince = nil }
                        else { self._slideSince = Date() }
                    }
                }, child: Text(paused ? "Resume" : "Pause")),
                gap(),
                Text(clock(_slideElapsed)),
                gap(),
                Button(onPressed: { [weak self] in self?.setState { self?._slideBanked = 0; self?._slideSince = Date() } }, child: Text("Repeat")),
                gap(),
                Text("Total \(clock(_rehearsedTotal))"),
            ]))))
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
            AspectRatio(aspectRatio: deck.slideSize.width / deck.slideSize.height, child: ClipRect(child: CustomPaint(
                painter: SlidePainter(slide: deck.slides[i], theme: deck.theme, slideSize: deck.slideSize,
                                      revision: deck.revision, cache: _cache, placeholders: false),
                child: SizedBox(expand: ()))))
        } ?? label("End of slide show", 16, dim)
        let remaining = _at < _order.count ? max(0, _plan.groups.count - _played) : 0
        let notes = _at < _order.count ? deck.slides[_order[_at]].notes.document.plainText() : ""
        let t = Int(_elapsed)
        let timer = String(printf: "%d:%02d:%02d", Int32(t / 3600), Int32((t / 60) % 60), Int32(t % 60))
        let clock = OfficeDates.format(Date(), "h:mm a")
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
            button("A−") { [weak self] in self?.setState { self?._notesSize = max(12, (self?._notesSize ?? 22) - 2) } },
            SizedBox(width: 4, height: nil, child: nil),
            button("A+") { [weak self] in self?.setState { self?._notesSize = min(48, (self?._notesSize ?? 22) + 2) } },
            SizedBox(width: 12, height: nil, child: nil),
            button(_blank == nil ? "Black" : "Unblack") { [weak self] in
                self?.setState { self?._blank = self?._blank == nil ? Color(0xFF000000) : nil }
            },
            SizedBox(width: 6, height: nil, child: nil),
            button(_seeAll ? "Hide slides" : "See all slides") { [weak self] in self?.setState { self?._seeAll.toggle() } },
            Expanded(child: Center(child: label(counter, 18, white))),
            label(clock, 22, white),
            SizedBox(width: 16, height: nil, child: nil),
            button("End Show") { [weak self] in self?._w.onEnd() },
        ]))
        // "See all slides": every slide of the show's order as a thumbnail; a click jumps there.
        let grid = SingleChildScrollView(child: Wrap(spacing: 10, runSpacing: 10, children: _order.enumerated().map { pos, i in
            Listener(onPointerDown: { [weak self] _ in
                guard let self else { return }
                self.setState { self._seeAll = false }
                self._go(to: pos, animate: false)
            }, child: SizedBox(width: 190, height: 190 * deck.slideSize.height / deck.slideSize.width + 18, child: Column(
                crossAxisAlignment: .start, children: [
                    AspectRatio(aspectRatio: deck.slideSize.width / deck.slideSize.height, child: ClipRect(child: CustomPaint(
                        painter: SlidePainter(slide: deck.slides[i], theme: deck.theme, slideSize: deck.slideSize,
                                              revision: deck.revision, cache: _cache, placeholders: false),
                        child: SizedBox(expand: ())))),
                    label("\(i + 1)", 12, pos == _at ? white : dim),
                ])))
        }))
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
                        Expanded(child: _seeAll ? grid : show),
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
                            style: Flutter.TextStyle(color: notes.isEmpty ? dim : white, fontSize: _notesSize, height: 1.35, fontFamily: font)))),
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
                if e.kind == .touch, !self._w.landing {
                    // A finger decides on lifting: a tap, a swipe, or a hold that raises the controls. A second finger
                    // landing (a two-finger tap) raises them too and is no tap for either finger.
                    let second = self._touch.down(e) { [weak self] _ in self?._showControls(fromHold: true) }
                    self._touchStart = second ? nil : e.position
                    if self._touchStart != nil { self._controlsOpenedByThisTouch = false }
                    return
                }
                self._press(at: e.position, secondary: e.buttons & kSecondaryMouseButton != 0, context: context)
            },
            onPointerMove: { [weak self] e in self?._touch.moved(e.pointer, e.position) },
            onPointerUp: { [weak self] e in
                guard let self else { return }
                if e.kind == .touch, !self._w.landing {
                    self._touch.up(e.pointer)
                    guard let start = self._touchStart else { return }
                    self._touchStart = nil
                    if self._controlsOpenedByThisTouch { self._controlsOpenedByThisTouch = false; return }
                    if self._controlsShown { self._hideControls(); return }   // a touch elsewhere puts the controls away
                    switch Self.touchStep(from: start, to: e.position) {
                    case .tap: self._press(at: e.position, secondary: false, context: context)
                    case .next: self._next()
                    case .previous: self._previous()
                    case .none: break
                    }
                    return
                }
                guard self._w.landing, let start = self._pointerStart else { return }
                self._pointerStart = nil
                let dx = e.position.dx - start.dx, dy = e.position.dy - start.dy
                if abs(dx) > 40 && abs(dx) > abs(dy) {
                    if dx > 0 { self._previous() } else { self._next() }
                } else if abs(dx) < 12 && abs(dy) < 12 { self._next() }
            },
            onPointerHover: { [weak self] _ in
                guard let self, !self._w.presenter else { return }
                self._hideCursorSoon()
            },
            onPointerCancel: { [weak self] e in
                self?._pointerStart = nil
                self?._touchStart = nil
                self?._touch.up(e.pointer)
            },
            behavior: .opaque,
            child: CustomPaint(
                painter: _ShowPainter(current: current, previous: progress < 1 ? previous : nil,
                                      progress: progress, theme: deck.theme, slideSize: deck.slideSize,
                                      cache: _cache, blank: _blank, reveals: reveals, videoFrames: _videoFrames,
                                      letterbox: _w.landing ? (current?.background?.color ?? deck.theme.background) : nil,
                                      assetRevision: _assetRevision,
                                      revision: deck.revision &+ Int(progress * 1000) &+ (_blank == nil ? 0 : 7) &+ _at * 10007
                                          &+ _played * 131 &+ _frameSerial &* 977 &+ _videoFrames.keys.reduce(0, &+) &+ Int((elapsed ?? -1) * 1000) * 7919),
                child: SizedBox(expand: ())))
        let body: Widget = _w.presenter ? _presenterView(context, show: show) : show
        var layers: [Widget] = [body]
        if _controlsShown, !_w.presenter { layers.append(_touchControls(context)) }
        if _w.rehearse { layers.append(_rehearseBar(context)) }
        // The show covers the editor: the keyboard and a screen reader stay in the show until it ends.
        return KeyboardRegion(name: "Slide Show", modal: true, child: layers.count > 1 ? Stack(children: layers) : body)
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
    let videoFrames: [Int: Image]
    let letterbox: Color?
    let assetRevision: Int
    let revision: Int

    init(current: Slide?, previous: Slide?, progress: Double, theme: DeckTheme, slideSize: Size,
         cache: SlideTextCache, blank: Color?, reveals: ShapeReveals, videoFrames: [Int: Image] = [:], letterbox: Color? = nil, assetRevision: Int = 0, revision: Int) {
        self.current = current
        self.previous = previous
        self.progress = progress
        self.theme = theme
        self.slideSize = slideSize
        self.cache = cache
        self.blank = blank
        self.reveals = reveals
        self.videoFrames = videoFrames
        self.letterbox = letterbox
        self.assetRevision = assetRevision
        self.revision = revision
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let black = Paint()
        black.style = .fill
        black.color = blank ?? letterbox ?? Color(0xFF000000)
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
                         reveals: slide === current ? reveals : ShapeReveals(), placeholders: false)
                .paint(canvas, Size(w, h))
            if slide === current {
                // The playing clip's frame over its poster, fitted to the frame.
                let k = w / slideSize.width
                for shape in slide.shapes where shape.media != nil {
                    guard let img = videoFrames[shape.id] else { continue }
                    let f = shape.frame
                    let iw = Double(img.width), ih = Double(img.height)
                    let fit = min(f.width / iw, f.height / ih)
                    let dw = iw * fit, dh = ih * fit
                    let dst = Rect.fromLTWH((f.left + (f.width - dw) / 2) * k, (f.top + (f.height - dh) / 2) * k, dw * k, dh * k)
                    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), dst, Paint())
                }
            }
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
        case .pull:
            draw(current, at: .zero)
            draw(previous, at: Offset(-dx * t, -dy * t))
        case .split:
            // The new slide opens from the middle (out) or closes in from both edges (in), in two halves.
            let tr = current.transition
            draw(previous, at: .zero)
            let bars: [Rect]
            let cx = box.left + w / 2, cy = box.top + h / 2
            if tr.vertical {
                let half = h / 2 * t
                bars = tr.inward
                    ? [Rect.fromLTRB(box.left, box.top, box.right, box.top + half), Rect.fromLTRB(box.left, box.bottom - half, box.right, box.bottom)]
                    : [Rect.fromLTRB(box.left, cy - half, box.right, cy + half)]
            } else {
                let half = w / 2 * t
                bars = tr.inward
                    ? [Rect.fromLTRB(box.left, box.top, box.left + half, box.bottom), Rect.fromLTRB(box.right - half, box.top, box.right, box.bottom)]
                    : [Rect.fromLTRB(cx - half, box.top, cx + half, box.bottom)]
            }
            for bar in bars {
                canvas.save()
                canvas.clipRect(bar)
                draw(current, at: .zero)
                canvas.restore()
            }
        case .zoom:
            // In: the new slide grows from the middle over the old one. Out: the old one shrinks away.
            let growing = current.transition.zoomIn
            draw(growing ? previous : current, at: .zero)
            let scale = growing ? t : 1 - t
            canvas.save()
            canvas.translate(box.left + w / 2, box.top + h / 2)
            canvas.scale(scale, scale)
            canvas.translate(-(box.left + w / 2), -(box.top + h / 2))
            draw(growing ? current : previous, at: .zero)
            canvas.restore()
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
        return old.assetRevision != assetRevision || old.revision != revision || old.current !== current || old.previous !== previous
    }
}
