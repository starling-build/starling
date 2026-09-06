// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - VideoPlayerWidget

class VideoPlayerWidget: StatefulWidget {
    let path: String

    init(path: String) {
        self.path = path
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _VideoPlayerState()
    }
}

// Playback is a reader thread per run: ffmpeg (spawned by PipeDecoder,
// realtime-paced) writes RGBA frames down a pipe, the reader blocks on
// whole frames and hands each to the main thread for texture upload. Pause,
// seek-to-start and file switches all work the same way — bump `generation`
// and kill the decoder; stale hops check the generation and evaporate. At
// most two frames are in flight (the semaphore), so a busy main thread
// backpressures ffmpeg through the pipe instead of ballooning memory.
class _VideoPlayerState: State<StatefulWidget> {
    private var textureId: Int64 = -1
    private var hasTexture = false
    private var info = VideoInfo()
    private var position: Double = 0
    private var isPlaying = false
    private var frameCount = 0
    private var currentPath = ""
    private var showOpenPanel = false
    private var decoder: PipeDecoder? = nil
    private var generation = 0
    /// Non-nil while the scrubber is being dragged: the position the thumb
    /// shows, distinct from playback position until the drag commits.
    private var scrubPosition: Double? = nil
    /// The scrubber's laid-out width, from MeasureSize — drag x → seconds.
    private var scrubberW: Double = 0
    /// Frame size the running decoder emits, which is the window size at the
    /// time it was spawned (see PipeDecoder.outputSize), not the file's.
    private var decodeW = 0
    private var decodeH = 0
    /// True while a resize respawn is waiting out its debounce.
    private var resizeRespawnPending = false
    /// Playback position last shown by a rebuild. The texture updates itself
    /// (the engine re-composites on the frame the update schedules), so the
    /// widget tree only needs rebuilding when the CHROME changes — the clock
    /// and the scrubber thumb — which nobody can read faster than this.
    private var lastShownPosition: Double = -1
    private static let kChromeUpdateInterval = 0.1
    #if os(Linux)
    /// Whether THIS file decodes on the GPU. Decided per file at open, by
    /// trying — hardware support is a property of the codec and the device,
    /// not of the machine.
    private var useHardware = false
    private var hwSource: H264Source? = nil
    #endif

    private static let kVideoExtensions = [
        "mp4", "mkv", "avi", "mov", "webm", "m4v", "mpg", "mpeg", "ts",
        "wmv", "flv", "ogv"]

    private var w: VideoPlayerWidget {
        widget as! VideoPlayerWidget
    }

    override func initState() {
        super.initState()

        #if os(Linux)
        if let rendererState = gpuDmaBufRendererState {
            textureId = rendererState.registerExternalTexture()
            hasTexture = true
        }
        #endif

        if !w.path.isEmpty {
            _openVideo(w.path)
        }
    }

    override func dispose() {
        generation += 1
        let dec = decoder
        decoder = nil
        DispatchQueue.global(qos: .utility).async { dec?.stop() }
        #if os(Linux)
        // Unregistering the texture below hands back every surface still
        // bound, so this stop is what closes the decoder behind them.
        let hw = hwSource
        hwSource = nil
        hw?.stop()
        #endif
        #if os(Linux)
        if hasTexture, let rendererState = gpuDmaBufRendererState {
            rendererState.unregisterExternalTexture(textureId)
        }
        #endif
        super.dispose()
    }

    /// (Re)opens a video: tears down any current run, keeps the registered
    /// texture, probes the file, and starts playing from the beginning.
    private func _openVideo(_ path: String) {
        _stopRun()
        // The MP4 index answers dimensions and duration for free; ffprobe
        // is the fallback for everything the narrow demuxer does not read.
        var probed: VideoInfo? = nil
        #if os(Linux)
        probed = H264Source.probe(path: path)
        #endif
        if probed == nil { probed = PipeDecoder.probe(path: path) }
        guard let probed, probed.width > 0, probed.height > 0 else {
            setState {
                currentPath = ""
                info = VideoInfo()
                frameCount = 0
            }
            return
        }
        #if os(Linux)
        useHardware = H264Source.canDecode(path: path)
        #endif
        setState {
            currentPath = path
            info = probed
            position = 0
            frameCount = 0
        }
        _startPlayback(from: 0)
    }

    /// Kill the current decode run; stale reader hops die on `generation`.
    private func _stopRun() {
        generation += 1
        isPlaying = false
        let dec = decoder
        decoder = nil
        DispatchQueue.global(qos: .utility).async { dec?.stop() }
        #if os(Linux)
        // Only unblock the reader — the decoder itself is torn down by its
        // last reference going away, which may be a release closure the
        // compositor is still holding for a surface it has bound.
        let hw = hwSource
        hwSource = nil
        hw?.stop()
        #endif
    }

    /// Jump to `target`. Playing: restart the stream there. Paused: decode
    /// exactly one frame there so the scrubber shows where it landed, then
    /// stop again.
    private func _seek(to target: Double) {
        let t = min(max(0, target), max(0, info.duration - 0.5))
        let wasPlaying = isPlaying
        _stopRun()
        setState { position = t }
        lastShownPosition = -1
        _startPlayback(from: t, pauseOnFirstFrame: !wasPlaying)
    }

    /// The window in physical pixels — the video texture covers all of it, so
    /// that is exactly the resolution worth decoding at. Nil before the view
    /// exists, which means "don't cap yet".
    private func _windowPixels() -> (width: Int, height: Int)? {
        guard let view = PlatformDispatcher.instance.implicitView else { return nil }
        let s = view.physicalSize
        guard s.width >= 2, s.height >= 2 else { return nil }
        return (Int(s.width.rounded()), Int(s.height.rounded()))
    }

    /// Whether the window has grown enough past the running decode to be
    /// visibly upscaling it. A few percent of slack keeps a resize drag from
    /// respawning ffmpeg for a change nobody can see; once the source itself
    /// is the cap, `outputSize` stops growing and this stays false.
    private func _windowOutgrewDecode() -> Bool {
        guard let px = _windowPixels() else { return false }
        let want = PipeDecoder.outputSize(for: info, maxWidth: px.width,
                                          maxHeight: px.height)
        return want.width * 32 > decodeW * 33 || want.height * 32 > decodeH * 33
    }

    /// A window that has grown past the frames feeding it is showing an
    /// upscaled picture, so respawn ffmpeg at the new size — from the current
    /// position, keeping play/pause. Shrinking is left alone; the extra detail
    /// costs nothing to keep until the run ends on its own.
    ///
    /// Waits for the size to hold still first: a drag walks through dozens of
    /// sizes and each respawn is a process launch plus a keyframe seek. The
    /// arm is one-shot — re-arming on every call would be no debounce at all,
    /// because playback rebuilds ~30 times a second and each rebuild would
    /// cancel the pending respawn before it could ever fire.
    private func _matchDecodeToWindow() {
        guard !resizeRespawnPending, decoder != nil, decodeW > 0,
              let armedAt = _windowPixels(), _windowOutgrewDecode() else { return }
        resizeRespawnPending = true
        let respawn: () -> Void = { [weak self] in
            guard let self else { return }
            self.resizeRespawnPending = false
            guard self.decoder != nil, self._windowOutgrewDecode(),
                  let now = self._windowPixels() else { return }
            // Still moving — leave it to the next rebuild to arm again rather
            // than decode into a size that is about to change.
            guard now == armedAt else { return }
            self._seek(to: self.position)
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.4,
            execute: unsafeBitCast(respawn, to: (@Sendable () -> Void).self))
    }

    private func _startPlayback(from start: Double,
                                pauseOnFirstFrame: Bool = false) {
        guard !currentPath.isEmpty, info.width > 0, hasTexture else { return }

        #if os(Linux)
        if useHardware {
            _startHardwarePlayback(from: start, pauseOnFirstFrame: pauseOnFirstFrame)
            return
        }
        #endif

        generation += 1
        let gen = generation
        let cap = _windowPixels() ?? (info.width, info.height)
        guard let dec = PipeDecoder(path: currentPath, start: start, info: info,
                                    maxWidth: cap.width,
                                    maxHeight: cap.height) else { return }
        decoder = dec
        isPlaying = !pauseOnFirstFrame

        // The pipe carries dec's frames, which are the window's size, not the
        // file's — sizing the read buffer from `info` would tear every frame.
        let vw = dec.outWidth, vh = dec.outHeight
        decodeW = vw
        decodeH = vh
        let fps = info.fps
        let texId = textureId
        let inFlight = DispatchSemaphore(value: 2)

        // The state class is not Sendable; the reader reaches back through
        // main-queue hops that only touch it after the generation check —
        // the same unsafeBitCast coercion the shell uses for its timers.
        let readerBody: () -> Void = { [weak self] in
            // The reader paces playback (ffmpeg decodes as fast as we read;
            // see PipeDecoder on why -re is wrong here): one frame per
            // interval against a start-anchored clock, so decode jitter
            // doesn't accumulate. The first frame goes out immediately —
            // it's the one a seek is waiting to show.
            var startedAt = timespec()
            clock_gettime(CLOCK_MONOTONIC, &startedAt)
            let t0 = Double(startedAt.tv_sec) + Double(startedAt.tv_nsec) / 1e9
            var framesRead = 0
            while true {
                var frame = [UInt8](repeating: 0, count: vw * vh * 4)
                guard dec.readFrame(into: &frame) else { break }
                if framesRead > 0 {
                    var now = timespec()
                    clock_gettime(CLOCK_MONOTONIC, &now)
                    let elapsed = Double(now.tv_sec) + Double(now.tv_nsec) / 1e9 - t0
                    let due = Double(framesRead) / fps
                    if due > elapsed {
                        usleep(useconds_t((due - elapsed) * 1_000_000))
                    }
                }
                framesRead += 1
                let thisFrame = framesRead  // by value — deliver runs later
                let pos = dec.startPosition + Double(framesRead) / fps
                inFlight.wait()
                let deliver: () -> Void = { [weak self] in
                    defer { inFlight.signal() }
                    guard let self, self.generation == gen else { return }
                    #if os(Linux)
                    gpuDmaBufRendererState?.updateExternalTexturePixels(
                        texId, pixels: frame, width: Int32(vw), height: Int32(vh))
                    #endif
                    self.frameCount += 1
                    self.position = pos
                    self._rebuildChromeIfDue(pos)
                    // A paused seek wants exactly this one frame on screen;
                    // stopping bumps the generation, so the reader's later
                    // hops (and its EOF loop) all evaporate.
                    if pauseOnFirstFrame && thisFrame == 1 {
                        self._stopRun()
                        self.setState { self.position = pos }
                    }
                }
                DispatchQueue.main.async(
                    execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
            }
            // EOF (a stop bumps the generation first, so this really is the
            // end of the file): loop from the top, like the old player.
            let loop: () -> Void = { [weak self] in
                guard let self, self.generation == gen, self.isPlaying
                else { return }
                self._startPlayback(from: 0)
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(loop, to: (@Sendable () -> Void).self))
        }
        let reader = Thread(
            block: unsafeBitCast(readerBody, to: (@Sendable () -> Void).self))
        reader.name = "video-reader"
        reader.start()
    }

    #if os(Linux)
    /// The zero-copy run: the GPU decodes into a DMA-BUF and the compositor
    /// samples it. Same shape as the pipe reader above — same pacing clock,
    /// same generation checks, same two-frames-in-flight bound — but a frame
    /// is a buffer handle rather than 16MB of RGBA, so nothing is read, copied
    /// or uploaded.
    ///
    /// Decoding happens at the file's own resolution here. Scaling to the
    /// window exists to shrink an upload that no longer occurs; the GPU
    /// samples whatever size the surface is for free.
    private func _startHardwarePlayback(from start: Double,
                                        pauseOnFirstFrame: Bool) {
        generation += 1
        let gen = generation
        guard let src = H264Source(path: currentPath, start: start) else {
            // The device or the codec dropped out from under us; the software
            // path still works, so fall back rather than show nothing.
            useHardware = false
            _startPlayback(from: start, pauseOnFirstFrame: pauseOnFirstFrame)
            return
        }
        hwSource = src
        isPlaying = !pauseOnFirstFrame
        decodeW = info.width
        decodeH = info.height

        let fps = info.fps
        let texId = textureId
        let inFlight = DispatchSemaphore(value: 2)

        let readerBody: () -> Void = { [weak self] in
            var startedAt = timespec()
            clock_gettime(CLOCK_MONOTONIC, &startedAt)
            let t0 = Double(startedAt.tv_sec) + Double(startedAt.tv_nsec) / 1e9
            var framesRead = 0
            while true {
                guard let f = src.next() else { break }
                // Paced against the frame's OWN timestamp, not a frame
                // count: this path hands over the file's real frames rather
                // than ffmpeg's CFR resampling of them, and on a screen
                // recording the gaps between them are real — 297 frames
                // spread unevenly over 40s. Counting would play those at a
                // uniform rate and lose the timing entirely.
                let pos = f.position > 0 ? f.position
                    : src.startPosition + Double(framesRead) / fps
                if framesRead > 0 {
                    var now = timespec()
                    clock_gettime(CLOCK_MONOTONIC, &now)
                    let elapsed = Double(now.tv_sec) + Double(now.tv_nsec) / 1e9 - t0
                    let due = pos - src.startPosition
                    if due > elapsed {
                        usleep(useconds_t(min(due - elapsed, 1.0) * 1_000_000))
                    }
                }
                framesRead += 1
                let thisFrame = framesRead
                inFlight.wait()
                let token = f.token
                let deliver: () -> Void = { [weak self] in
                    defer { inFlight.signal() }
                    guard let self, self.generation == gen else {
                        src.release(token)
                        return
                    }
                    // `release` runs on the raster thread once a later surface
                    // has been bound. Capturing `src` strongly is what keeps
                    // the decoder alive for exactly that long.
                    gpuDmaBufRendererState?.updateExternalTextureNV12(
                        texId, fd: f.fd, width: f.width, height: f.height,
                        modifier: f.modifier,
                        offset0: f.offset0, pitch0: f.pitch0,
                        offset1: f.offset1, pitch1: f.pitch1,
                        release: { src.release(token) })
                    self.frameCount += 1
                    self.position = pos
                    self._rebuildChromeIfDue(pos)
                    if pauseOnFirstFrame && thisFrame == 1 {
                        self._stopRun()
                        self.setState { self.position = pos }
                    }
                }
                DispatchQueue.main.async(
                    execute: unsafeBitCast(deliver, to: (@Sendable () -> Void).self))
            }
            // The run is over however it ended — end of file or a stop that
            // was already signalled. Marking it closes the decoder as soon as
            // the compositor gives the last surface back, which for a loop is
            // the moment the next run's first frame binds. Without this an
            // EOF-ended run would keep its VA-API context for good.
            src.stop()
            let loop: () -> Void = { [weak self] in
                guard let self, self.generation == gen, self.isPlaying
                else { return }
                self._startPlayback(from: 0)
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(loop, to: (@Sendable () -> Void).self))
        }
        let reader = Thread(
            block: unsafeBitCast(readerBody, to: (@Sendable () -> Void).self))
        reader.name = "video-reader-hw"
        reader.start()
    }
    #endif

    /// Rebuild only when the visible chrome would actually change. The first
    /// frame always rebuilds — it is the one that swaps "Loading…" for the
    /// texture — and after that a rebuild is worth it at most ten times a
    /// second, which is finer than the clock's one-second resolution and
    /// finer than the eye reads a moving thumb.
    private func _rebuildChromeIfDue(_ pos: Double) {
        if frameCount > 1,
           abs(pos - lastShownPosition) < Self.kChromeUpdateInterval {
            return
        }
        lastShownPosition = pos
        setState {}
    }

    private func _togglePlay() {
        if isPlaying {
            setState { _stopRun() }
        } else {
            // Resume near the end restarts — matching the loop behaviour.
            let from = position >= info.duration - 0.3 ? 0 : position
            setState { _startPlayback(from: from) }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        // A window resize rebuilds; playback rebuilds every frame anyway. The
        // check is two comparisons and only the growth case does any work.
        _matchDecodeToWindow()

        var children: [Widget] = []

        if hasTexture && frameCount > 0 {
            // Decoded frames are top-row-first; the engine samples external GL
            // textures as kBottomLeft, so counter with a Y-flip (same as the
            // shell's flipTextureY for Wayland surfaces).
            children.append(
                Positioned(
                    fill: (),
                    child: Transform(
                        transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                        alignment: Alignment.center,
                        child: TextureWidget(textureId: Int(textureId))
                    )
                )
            )
        } else {
            children.append(
                Positioned(
                    fill: (),
                    child: ColoredBox(
                        color: Color(0xFF000000),
                        child: Center(
                            child: Text(
                                !currentPath.isEmpty ? "Loading..."
                                    : "No video \u{2014} click Open\u{2026}",
                                style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 18)
                            )
                        )
                    )
                )
            )
        }

        // Controls — the QuickTime shape: dark translucent bar, filled
        // play/pause glyph, monospace-ish times flanking the scrubber.
        children.append(
            Positioned(
                left: 0, right: 0, bottom: 0,
                height: 44,
                child: ColoredBox(
                    color: Color(rgbo: 22, 22, 24, 0.72),
                    child: Padding(
                        padding: EdgeInsets(left: 14, right: 14),
                        child: Row(
                            crossAxisAlignment: .center,
                            children: [
                                GestureDetector(
                                    onTap: { [self] in _togglePlay() },
                                    behavior: .opaque,
                                    child: Padding(
                                        padding: EdgeInsets(left: 2, top: 8, right: 10, bottom: 8),
                                        child: Icon(
                                            isPlaying
                                                ? FluentSystemIcons.pause
                                                : FluentSystemIcons.play,
                                            size: 16,
                                            color: Color(0xFFFFFFFF)
                                        )
                                    )
                                ),
                                Text(
                                    _formatTime(scrubPosition ?? position),
                                    style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12)
                                ),
                                SizedBox(width: 10),
                                Expanded(child: _scrubber()),
                                SizedBox(width: 10),
                                Text(
                                    _formatTime(info.duration),
                                    style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 12)
                                ),
                                SizedBox(width: 6),
                                GestureDetector(
                                    onTap: { [self] in
                                        setState { showOpenPanel = true }
                                    },
                                    behavior: .opaque,
                                    child: Padding(
                                        padding: EdgeInsets(all: 6),
                                        child: Text(
                                            "Open\u{2026}",
                                            style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 12)
                                        )
                                    )
                                ),
                            ]
                        )
                    )
                )
            )
        )

        // Shared system open dialog, filtered to video types.
        if showOpenPanel {
            var opts = MacosFilePanelOptions()
            opts.mode = .open
            opts.title = "Open Video"
            opts.appearanceDark = true   // the player chrome is always dark
            opts.allowedExtensions = Self.kVideoExtensions
            opts.initialDirectory = currentPath.isEmpty
                ? nil
                : (currentPath as NSString).deletingLastPathComponent
            children.append(Positioned(
                fill: (),
                child: MacosFilePanelOverlay(options: opts) { [self] paths in
                    setState { showOpenPanel = false }
                    if let path = paths.first {
                        _openVideo(path)
                    }
                }
            ))
        }

        return Stack(fit: .expand, children: children)
    }

    private func _formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Scrubber

    /// macOS-style scrubber: thin rounded track, filled to the playhead, a
    /// round thumb. Click jumps; drag shows the target (scrubPosition) and
    /// seeks on release — one decoder respawn per gesture, not per pixel.
    /// MacosSlider in the framework is display-only, so this is hand-built
    /// on the drag callbacks; the width comes from MeasureSize.
    private func _scrubber() -> Widget {
        let dur = max(info.duration, 0.001)
        let fraction = min(max((scrubPosition ?? position) / dur, 0), 1)
        let thumbD = 12.0
        let trackH = 4.0
        let rowH = 44.0
        let usable = max(scrubberW - thumbD, 1)
        let thumbX = usable * fraction

        func target(_ x: Double) -> Double {
            guard scrubberW > thumbD else { return position }
            return min(max((x - thumbD / 2) / usable, 0), 1) * dur
        }

        return GestureDetector(
            onTapUp: { [self] d in
                guard info.duration > 0 else { return }
                _seek(to: target(d.localPosition.dx))
            },
            onHorizontalDragStart: { [self] d in
                guard info.duration > 0 else { return }
                setState { scrubPosition = target(d.localPosition.dx) }
            },
            onHorizontalDragUpdate: { [self] d in
                guard scrubPosition != nil else { return }
                setState { scrubPosition = target(d.localPosition.dx) }
            },
            onHorizontalDragEnd: { [self] _ in
                guard let t = scrubPosition else { return }
                setState { scrubPosition = nil }
                _seek(to: t)
            },
            behavior: .opaque,
            child: MeasureSize(
                onSize: { [weak self] size in
                    self?._recordScrubberWidth(size.width)
                },
                child: SizedBox(
                    height: rowH,
                    child: Stack(children: [
                        Positioned(
                            left: 0, top: (rowH - trackH) / 2, right: 0,
                            height: trackH,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Color(rgbo: 255, 255, 255, 0.25),
                                    borderRadius: BorderRadius.circular(trackH / 2)
                                )
                            )
                        ),
                        Positioned(
                            left: 0, top: (rowH - trackH) / 2,
                            width: max(thumbX + thumbD / 2, trackH),
                            height: trackH,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Color(rgbo: 255, 255, 255, 0.9),
                                    borderRadius: BorderRadius.circular(trackH / 2)
                                )
                            )
                        ),
                        Positioned(
                            left: thumbX, top: (rowH - thumbD) / 2,
                            width: thumbD, height: thumbD,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(thumbD / 2),
                                    boxShadow: [BoxShadow(
                                        color: Color(rgbo: 0, 0, 0, 0.35),
                                        offset: Offset(0, 1),
                                        blurRadius: 2
                                    )]
                                )
                            )
                        ),
                    ])
                )
            )
        )
    }

    /// Fires from MeasureSize during layout — bounce to the main queue
    /// before touching state (the codebase-wide MeasureSize rule).
    private func _recordScrubberWidth(_ w: Double) {
        if abs(w - scrubberW) < 0.5 { return }
        let update: () -> Void = { [weak self] in
            guard let self else { return }
            self.setState { self.scrubberW = w }
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(update, to: (@Sendable () -> Void).self))
    }
}
