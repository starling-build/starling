// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StarlingRecord

#if os(Linux)
import Glibc
import FlutterDRMBridge

/// Owns a screen-recording session: engine frames in, a finished MP4 in
/// ~/Videos out — zero-copy through the GPU when the stack allows, through
/// StarlingRecord's ffmpeg pipe otherwise.
///
/// Two frame paths, chosen per session at start:
///
/// Zero-copy (VaapiEncoder): the engine blits each frame into a dmabuf ring
/// and hands fds to `ingestDmabuf` on its PRESENTING thread — queue and hop,
/// nothing heavier. The encode queue maps each fd into VAAPI, encodes on the
/// GPU, and releases the ring slot; pixels never touch the CPU and frames
/// carry real timestamps, so there is no pacer. If the engine cannot build
/// the ring it sends one sentinel frame (fd < 0) and falls back to CPU
/// frames mid-start — `swapToPipeEncoder` swaps the session onto the pipe
/// path without the user noticing.
///
/// Pipe (FfmpegEncoder): the engine delivers CPU frames on ITS recorder
/// writer thread — `ingest` copies into the mailbox under the lock and
/// returns. The pacer queue turns the mailbox into a constant 30fps stream
/// for ffmpeg: raw video over a pipe carries no timestamps, so pacing IS
/// the timeline — the last frame repeats while the desktop idles, extras
/// drop while it presents at 60.
///
/// `state`/`onChange` are main-thread only, like all shell state.
///
/// Present pump. The engine consumes start/stop requests on its presenting
/// thread, and an idle desktop never presents — the shell's 33ms frame-tick
/// timer must force composites from the moment a session starts until the
/// engine confirms the stop (`needsFramePump`), or the session never starts
/// and never ends. See fl_drm_view.h's recording block.
final class RecordingService {

    enum State { case idle, starting, recording, stopping }

    /// Main-thread only.
    private(set) var state: State = .idle
    private(set) var startedAt: Date? = nil
    private(set) var lastSavedPath: String? = nil
    var onChange: (() -> Void)?
    /// Fires on main after a session ends: (saved file, or nil) + detail.
    var onFinished: ((String?, String) -> Void)?

    static let fps = 30

    /// The tile dims itself on machines that cannot record (no ffmpeg
    /// binary for the pipe path AND no in-process zero-copy encoder).
    /// Checked once — packages don't come and go under a live session.
    lazy var available: Bool =
        FfmpegEncoder.findFfmpeg() != nil || resolveZeroCopyDevice() != nil

    // Probe results — real test opens, run once. Warmed in the background
    // at init so the first Record tap doesn't pay for them; the lock makes
    // a too-early tap wait instead of racing.
    private let hwLock = NSLock()
    private var hwProbed = false
    private var hwEncoder: HardwareEncoder?
    private var zcProbed = false
    private var zcDevice: String?

    init() {
        let warm: () -> Void = { [weak self] in
            _ = self?.resolveZeroCopyDevice()
            _ = self?.resolveHardwareEncoder()
        }
        queue.async(execute: unsafeBitCast(warm, to: (@Sendable () -> Void).self))
    }

    private func resolveHardwareEncoder() -> HardwareEncoder? {
        hwLock.lock()
        defer { hwLock.unlock() }
        if !hwProbed {
            if let ffmpeg = FfmpegEncoder.findFfmpeg() {
                hwEncoder = FfmpegEncoder.detectHardwareEncoder(ffmpegPath: ffmpeg)
            }
            hwProbed = true
            if hwEncoder == nil {
                let msg = "[Recording] no VAAPI encoder — software x264, "
                    + "large screens capture at half size\n"
                _ = msg.withCString { write(2, $0, strlen($0)) }
            }
        }
        return hwEncoder
    }

    /// Render node with a working in-process VAAPI path, or nil. When this
    /// resolves, sessions record zero-copy: dmabuf frames, GPU encode, no
    /// ffmpeg child, no pacer.
    private func resolveZeroCopyDevice() -> String? {
        hwLock.lock()
        defer { hwLock.unlock() }
        if !zcProbed {
            zcDevice = VaapiEncoder.detectDevice()
            zcProbed = true
            // Name the node. Which GPU encodes is a policy decision now (the
            // compositor's card, not whichever one probes first), and "ready"
            // alone cannot tell a right answer from a lucky one — on a
            // two-GPU box the wrong card fails later, at dma-buf import,
            // nowhere near the line that chose it.
            let msg = zcDevice.map {
                "[Recording] zero-copy VAAPI encoder ready on \($0)"
                + " (compositor's card)\n"
            } ?? "[Recording] no zero-copy encoder — pipe path\n"
            _ = msg.withCString { write(2, $0, strlen($0)) }
        }
        return zcDevice
    }

    /// What the last (or current) session captures at, and through which
    /// encoder — the broker reports these so tests assert the file against
    /// the shell's own claim rather than re-deriving the policy.
    private(set) var captureWidth = 0
    private(set) var captureHeight = 0
    private(set) var usingHardware = false
    private(set) var zeroCopy = false
    /// Timestamp of the last frame actually encoded, in the engine's
    /// microseconds — the zero-copy path's rate limiter. Touched only on
    /// `queue`, which is serial.
    private var lastEncodedUs: UInt64? = nil

    // The live session's engine-side frame size and output file — what a
    // mid-start fallback to the pipe encoder must recreate exactly (the
    // engine's dims are frozen; the URL was claimed and then deleted by
    // the aborted zero-copy encoder).
    private var engineWidth = 0
    private var engineHeight = 0
    private var sessionURL: URL?
    // Bumped per start; stale deadline checks compare against it.
    private var sessionGen = 0

    // MARK: - Recording zoom
    //
    // The recorded region, not the screen. A 4K capture delivered at 1080p
    // has 2x of zoom in hand — a 1:1 crop is pixel-native — so zooming the
    // CROP costs nothing and nobody watching the desk sees anything move.
    //
    // The engine freezes the output dimensions at start and scales whatever
    // crop it is given into them, so shrinking the crop IS the zoom. Only
    // the full-screen sink supports it: a window capture is already
    // crop-as-window (`set_crop` is how it tracks the window), and a second
    // meaning for the same call would fight it.

    /// Zoom steps. 1.0 is the whole output; 2.0 on a 4K panel is the 1:1
    /// crop, which is the sharpest a 1080p deliverable can be.
    static let zoomSteps: [Double] = [1.0, 1.5, 2.0, 3.0]

    /// While zoomed the crop follows the pointer — but only once it leaves
    /// the middle of the frame. The pointer may wander this fraction of the
    /// crop's half-extent from centre before the crop gives chase, and the
    /// chase moves just enough to hold it at that boundary. Without the
    /// dead zone every wiggle of narration drags the whole frame with it;
    /// without the chase the narrator walks the pointer out of their own
    /// shot and keeps talking about something the viewer cannot see.
    static let followSlack = 0.6

    /// Where the crop is heading, and where it is now — the gap between them
    /// is what `tickZoom` eases away. Fractions of the full framebuffer, so
    /// they survive a resolution change.
    private var zoomTarget: Double = 1.0
    private(set) var zoomLevel: Double = 1.0
    private var centerTarget = (x: 0.5, y: 0.5)
    private var center = (x: 0.5, y: 0.5)
    /// Full-resolution framebuffer size of the live session, for crop math.
    private var zoomFbWidth = 0
    private var zoomFbHeight = 0
    /// Window captures place the crop themselves; leave them alone.
    private var zoomSupported = false

    var isZoomed: Bool { zoomLevel > 1.001 || zoomTarget > 1.001 }
    /// "2.0" — for the menu-bar indicator, so the operator can see the state
    /// of a thing that is deliberately invisible on screen.
    var zoomLabel: String { String(format: "%.1f", zoomLevel) }

    /// Step in or out, keeping `at` (fractions of the screen) in frame. The
    /// centre is re-taken on every step, and between steps `tickZoom` pans
    /// after the pointer, so the zoom never commits to wherever it started.
    func stepZoom(_ delta: Int, at: (x: Double, y: Double)) {
        guard zoomSupported, isRecording else { return }
        let steps = Self.zoomSteps
        let i = steps.firstIndex(where: { $0 >= zoomTarget - 0.001 }) ?? 0
        let next = min(max(i + delta, 0), steps.count - 1)
        zoomTarget = steps[next]
        centerTarget = zoomTarget <= 1.001 ? (0.5, 0.5)
                                           : (min(max(at.x, 0), 1),
                                              min(max(at.y, 0), 1))
        onChange?()
    }

    func resetZoom() {
        zoomTarget = 1.0
        centerTarget = (0.5, 0.5)
    }

    /// Ease the live crop toward the target and push it to the engine.
    /// Driven by the shell's frame pump, which already runs while recording.
    /// `pointer` is the live cursor in fractions of the screen; while zoomed
    /// the crop pans to keep it in frame (see `followSlack`).
    func tickZoom(pointer: (x: Double, y: Double)? = nil) {
        guard zoomSupported, isRecording, zoomFbWidth > 0 else { return }
        if let p = pointer, zoomTarget > 1.001 { followPointer(p) }
        // Exponential ease: framerate-independent enough for a pump that is
        // not promised a fixed rate, and it never overshoots.
        let k = 0.18
        let done = abs(zoomTarget - zoomLevel) < 0.002
            && abs(centerTarget.x - center.x) < 0.001
            && abs(centerTarget.y - center.y) < 0.001
        // What the indicator shows, sampled before the tick moves it.
        let shownLabel = zoomLabel
        let shownZoomed = isZoomed
        if done {
            guard zoomLevel != zoomTarget || center != centerTarget else { return }
            zoomLevel = zoomTarget
            center = centerTarget
        } else {
            zoomLevel += (zoomTarget - zoomLevel) * k
            center.x += (centerTarget.x - center.x) * k
            center.y += (centerTarget.y - center.y) * k
        }
        pushCrop()
        // The indicator shows one decimal of zoom and nothing of the pan.
        // Rebuild the shell only when what it shows changed — a follow pan
        // ticks every frame the pointer moves, and setState per frame for
        // an invisible change is the rebuild storm the pump comment warns
        // about.
        if zoomLabel != shownLabel || isZoomed != shownZoomed { onChange?() }
    }

    /// Pan the crop after the pointer. Target-space on purpose: the dead
    /// zone is measured against `centerTarget` with the crop size at
    /// `zoomTarget`, so a mid-ease frame chases where it is going, not
    /// where it happens to be this tick.
    private func followPointer(_ p: (x: Double, y: Double)) {
        let half = 0.5 / zoomTarget
        let slack = half * Self.followSlack
        let px = min(max(p.x, 0), 1), py = min(max(p.y, 0), 1)
        if abs(px - centerTarget.x) > slack {
            centerTarget.x = px > centerTarget.x ? px - slack : px + slack
        }
        if abs(py - centerTarget.y) > slack {
            centerTarget.y = py > centerTarget.y ? py - slack : py + slack
        }
        // Keep the target where `pushCrop` can actually centre it, so at a
        // screen edge the dead zone is measured from the frame the viewer
        // really gets, not from an unreachable centre past the clamp.
        centerTarget.x = min(max(centerTarget.x, half), 1 - half)
        centerTarget.y = min(max(centerTarget.y, half), 1 - half)
    }

    private func pushCrop() {
        let fw = Double(zoomFbWidth), fh = Double(zoomFbHeight)
        let z = max(1.0, zoomLevel)
        let cw = (fw / z).rounded(), ch = (fh / z).rounded()
        // Clamp so the crop never leaves the framebuffer — the engine would
        // sample outside it, and the edge of a demo is exactly where the
        // pointer tends to be.
        let cx = min(max(center.x * fw - cw / 2, 0), fw - cw).rounded()
        let cy = min(max(center.y * fh - ch / 2, 0), fh - ch).rounded()
        fl_drm_view_recording_set_crop(Int32(cx), Int32(cy),
                                       Int32(cw), Int32(ch))
    }

    var isRecording: Bool { state == .starting || state == .recording }
    /// The frame-tick pump must run while this holds (see class comment).
    var needsFramePump: Bool { state != .idle }

    var elapsedSeconds: Int {
        guard let t = startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(t)))
    }

    // Mailbox: the newest engine frame. Written by the engine's writer
    // thread, drained by the pacer queue; the lock covers only the copy.
    private let mailboxLock = NSLock()
    private var mailbox: [UInt8] = []
    private var mailboxW = 0
    private var mailboxH = 0
    private var mailboxFresh = false

    private let queue = DispatchQueue(label: "starling.shell.record",
                                      qos: .userInitiated)
    private var pacer: DispatchSourceTimer?
    private var encoder: FfmpegEncoder?
    private var scratch: [UInt8] = []

    // Zero-copy path: dmabuf frames queued by the engine's presenting
    // thread, drained on `queue`. Slots are the engine's finite ring —
    // every queued frame either encodes or gets its slot released.
    private var vaapiEncoder: VaapiEncoder?
    private let dmabufLock = NSLock()
    private var dmabufPending: [FlDrmRecordDmabufFrame] = []

    // MARK: Frame ingest (engine writer thread)

    func ingest(_ rgba: UnsafePointer<UInt8>?, width: Int, height: Int) {
        guard let rgba, width > 0, height > 0 else { return }
        let bytes = width * height * 4
        mailboxLock.lock()
        if mailboxW != width || mailboxH != height {
            mailbox = [UInt8](repeating: 0, count: bytes)
            mailboxW = width
            mailboxH = height
        }
        mailbox.withUnsafeMutableBytes { buf in
            memcpy(buf.baseAddress!, rgba, bytes)
        }
        mailboxFresh = true
        mailboxLock.unlock()
    }

    // MARK: Source damage (any thread, from the texture registry)

    /// The texture an app recording is capturing, or -1. Read from
    /// whatever thread refreshes a texture, so it is a plain global rather
    /// than shell state: a stale read costs one keepalive frame, nothing
    /// more. Written on main at session start/end.
    nonisolated(unsafe) private(set) static var recordedTextureId: Int64 = -1

    /// A window's texture got new content. When it is the one being
    /// recorded, tell the engine — between commits the capture skips
    /// presents instead of encoding identical frames (fl_drm_view.h).
    static func noteSourceContentChanged(textureId: Int64) {
        guard textureId == recordedTextureId else { return }
        fl_drm_view_recording_notify_source_changed()
    }

    // MARK: Frame ingest, zero-copy (engine PRESENTING thread — queue and go)

    func ingestDmabuf(_ frame: FlDrmRecordDmabufFrame) {
        guard frame.fd >= 0 else {
            // Sentinel: the engine couldn't build the ring and the session
            // continues as CPU frames — swap to the pipe encoder.
            hopToMain { $0.swapToPipeEncoder() }
            return
        }
        dmabufLock.lock()
        dmabufPending.append(frame)
        dmabufLock.unlock()
        let drain: () -> Void = { [weak self] in self?.drainDmabuf() }
        queue.async(execute: unsafeBitCast(drain, to: (@Sendable () -> Void).self))
    }

    /// Encode queue: map each queued dmabuf into VAAPI, encode, release
    /// the ring slot. After endSession clears the encoder, queued frames
    /// only get their slots released — the footage ends at the stop.
    private func drainDmabuf() {
        while true {
            dmabufLock.lock()
            let frame = dmabufPending.isEmpty ? nil : dmabufPending.removeFirst()
            dmabufLock.unlock()
            guard let frame else { return }
            guard let enc = vaapiEncoder else {
                fl_drm_view_recording_release_dmabuf_slot(frame.slot)
                continue
            }
            // Safety net only: the ENGINE owns the frame-rate cap now
            // (fl_drm_view_recording_set_max_fps), paced on an absolute
            // schedule so a present missed to client jitter is repaid by
            // the next one — its catch-up frames arrive as little as one
            // vsync apart. A 30ms floor here silently discarded exactly
            // those frames and pinned recordings at ~27.6fps of the 30
            // requested. A third of the interval still guards against a
            // runaway engine without touching legitimate catch-up.
            let minGapUs = UInt64(1_000_000 / Self.fps) / 3
            if let last = lastEncodedUs, frame.timestamp_us >= last,
               frame.timestamp_us - last < minGapUs {
                fl_drm_view_recording_release_dmabuf_slot(frame.slot)
                continue
            }
            lastEncodedUs = frame.timestamp_us
            let ok = enc.encode(fd: frame.fd, stride: frame.stride,
                                offset: frame.offset, fourcc: frame.fourcc,
                                modifier: frame.modifier,
                                timestampUs: frame.timestamp_us)
            fl_drm_view_recording_release_dmabuf_slot(frame.slot)
            if !ok {
                let detail = "hardware encode failed: \(enc.errorOutput)"
                hopToMain { $0.endSession(reason: detail) }
                return
            }
            if enc.frameCount == 1 {
                hopToMain {
                    guard $0.state == .starting else { return }
                    $0.state = .recording
                    $0.onChange?()
                }
            }
        }
    }

    /// Mid-start fallback (main thread): the engine sent the dmabuf
    /// sentinel, so this session's frames arrive as CPU frames at the
    /// engine's frozen dims. Recreate the pipe encoder at those dims (its
    /// crop filter handles odd sizes) on the same output URL the aborted
    /// zero-copy encoder just vacated, and start the pacer.
    private func swapToPipeEncoder() {
        guard state == .starting || state == .recording, zeroCopy else { return }
        zeroCopy = false
        vaapiEncoder?.abort()
        vaapiEncoder = nil
        guard let ffmpeg = FfmpegEncoder.findFfmpeg(), let url = sessionURL else {
            endSession(reason: "ffmpeg is not installed")
            return
        }
        let hw = resolveHardwareEncoder()
        guard let enc = try? FfmpegEncoder(width: engineWidth,
                                           height: engineHeight,
                                           fps: Self.fps, outputURL: url,
                                           ffmpegPath: ffmpeg,
                                           hardware: hw) else {
            endSession(reason: "could not start ffmpeg")
            return
        }
        encoder = enc
        usingHardware = hw != nil
        captureWidth = engineWidth
        captureHeight = engineHeight
        startPacer(deadline: Date().addingTimeInterval(3))
    }

    // MARK: Session control (main thread)

    /// Window recording: true while the recorded window still exists (it
    /// may be minimized or covered — the capture doesn't care). Read on
    /// main by checkWindowAlive.
    private var windowAlive: (() -> Bool)? = nil
    /// The recorded window's CONTENT rect on screen (physical px), or nil
    /// while it isn't on screen at all — minimized, or parked on another
    /// space. A window-space capture cannot place a screen-space pointer
    /// without it, so this is what puts the cursor in an app recording;
    /// pushed every frame tick so a drag or resize keeps it honest. Main
    /// thread, like windowAlive.
    private var windowRect: (() -> (Int, Int, Int, Int)?)? = nil
    /// The recorded window's display name (nil = whole screen).
    private(set) var windowLabel: String? = nil

    /// Record the whole screen, or — with a texture — one app: the engine
    /// reads the window's OWN composited content (the texture the
    /// compositor draws), so other windows overlapping it, moves, even
    /// minimizing never show in the footage. Output size freezes at
    /// (width, height); the source scales to fit if the window resizes.
    func start(texture: Int64? = nil, width: Int = 0, height: Int = 0,
               textureTopDown: Bool = false,
               windowAlive alive: (() -> Bool)? = nil,
               windowRect rect: (() -> (Int, Int, Int, Int)?)? = nil,
               windowLabel label: String? = nil) {
        guard state == .idle else { return }
        // The engine runs one capture session; a live screen share owns it.
        guard !ScreenCastService.captureActive else {
            onFinished?(nil, "screen sharing is using the capture")
            return
        }
        // …and so does a connected RDP client, for the same reason.
        guard !RdpService.captureActive else {
            onFinished?(nil, "a remote desktop client is using the capture")
            return
        }
        guard let view = drmViewHandle else {
            onFinished?(nil, "no display")
            return
        }
        let ffmpeg = FfmpegEncoder.findFfmpeg()
        let zcDevice = resolveZeroCopyDevice()
        guard ffmpeg != nil || zcDevice != nil else {
            onFinished?(nil, "ffmpeg is not installed")
            return
        }
        let w = texture != nil ? width : Int(fl_drm_view_get_width(view))
        let h = texture != nil ? height : Int(fl_drm_view_get_height(view))
        guard w > 0, h > 0 else { return }

        let dir = RecordingPaths.videosDir(home: LoginUser.home)
        Self.ensureOwnedDir(dir)
        let url = RecordingPaths.outputURL(in: dir, now: Date(), label: label)

        var shift = 0
        if let device = zcDevice,
           let zc = VaapiEncoder(device: device, inWidth: w, inHeight: h,
                                 width: max(2, w & ~1),
                                 height: max(2, h & ~1),
                                 fps: Self.fps, outputURL: url) {
            // Zero-copy: full resolution always (the GPU encodes it for
            // free, and the transport is free too — that is the point).
            vaapiEncoder = zc
            encoder = nil
            zeroCopy = true
            usingHardware = true
            captureWidth = zc.width
            captureHeight = zc.height
            fl_drm_view_recording_set_dmabuf(1)
        } else {
            guard let ffmpeg else {
                onFinished?(nil, "ffmpeg is not installed")
                return
            }
            // Hardware encodes the full screen for free; software x264 at
            // 4K starved a real desktop into unresponsiveness, so it
            // captures at half size (the engine downscales on the GPU,
            // not us).
            let hw = resolveHardwareEncoder()
            shift = FfmpegEncoder.downscaleShift(width: w, height: h,
                                                 hardware: hw != nil)
            let cw = max(1, w >> shift)
            let ch = max(1, h >> shift)
            guard let enc = try? FfmpegEncoder(width: cw, height: ch,
                                               fps: Self.fps, outputURL: url,
                                               ffmpegPath: ffmpeg,
                                               hardware: hw) else {
                onFinished?(nil, "could not start ffmpeg")
                return
            }
            encoder = enc
            vaapiEncoder = nil
            zeroCopy = false
            usingHardware = hw != nil
            captureWidth = cw
            captureHeight = ch
            fl_drm_view_recording_set_dmabuf(0)
        }

        mailboxLock.lock()
        mailboxFresh = false
        mailboxLock.unlock()
        dmabufLock.lock()
        dmabufPending.removeAll()
        dmabufLock.unlock()

        engineWidth = max(1, w >> shift)
        engineHeight = max(1, h >> shift)
        sessionURL = url
        sessionGen += 1
        self.windowAlive = alive
        self.windowRect = rect
        self.windowLabel = label
        Self.recordedTextureId = texture ?? -1
        state = .starting
        // Runs on the same serial queue drainDmabuf uses, so the reset cannot
        // race a frame from the previous session still in flight.
        let reset: () -> Void = { [weak self] in self?.lastEncodedUs = nil }
        queue.async(execute: unsafeBitCast(reset, to: (@Sendable () -> Void).self))
        startedAt = Date()
        // Cap the capture rate in the ENGINE, not just here. Without it the
        // capture blit runs once per present — a 90Hz panel blits three
        // 2560x1600 frames into linear memory for every one a 30fps session
        // keeps, each of them ahead of the swap in the present path.
        // drainDmabuf's own cap then threw the extras away downstream,
        // after they had already cost their bandwidth; it stays as the
        // safety net.
        fl_drm_view_recording_set_max_fps(Int32(Self.fps))
        // Zoom starts off and is only offered to the full-screen sink; a
        // window capture drives `set_crop` itself to track its window.
        zoomLevel = 1.0; zoomTarget = 1.0
        center = (0.5, 0.5); centerTarget = (0.5, 0.5)
        zoomFbWidth = w; zoomFbHeight = h
        zoomSupported = (texture == nil)
        if let texture {
            fl_drm_view_recording_start_texture(view, Int32(shift), texture,
                                                Int32(w), Int32(h),
                                                textureTopDown ? 1 : 0)
            refreshWindowRect()
        } else {
            fl_drm_view_recording_start(view, Int32(shift))
        }
        if zeroCopy {
            scheduleZeroCopyDeadline(generation: sessionGen)
        } else {
            startPacer(deadline: Date().addingTimeInterval(3))
        }
        onChange?()
    }

    /// The zero-copy twin of the pacer's start deadline: no pacer runs, so
    /// a session the engine never feeds (callback unwired, ES3 missing)
    /// must be failed from here rather than sitting in .starting forever.
    private func scheduleZeroCopyDeadline(generation: Int) {
        let check: () -> Void = { [weak self] in
            guard let self, self.sessionGen == generation,
                  self.state == .starting, self.zeroCopy else { return }
            self.endSession(reason: "the engine delivered no frames")
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 3,
            execute: unsafeBitCast(check, to: (@Sendable () -> Void).self))
    }

    /// Called from the shell's frame-tick pump while recording: end the
    /// session (the footage so far is saved) when the recorded window
    /// goes away. Minimized/covered is NOT gone — the capture reads the
    /// window's own texture.
    func checkWindowAlive() {
        guard state == .starting || state == .recording,
              let alive = windowAlive, !alive() else { return }
        stop()
    }

    /// Called from the shell's frame-tick pump beside checkWindowAlive:
    /// tell the engine where the recorded window's content currently is, so
    /// the cursor is composited in the right place. Off screen (minimized,
    /// another space) pushes an empty rect, which leaves the cursor out
    /// rather than drawing it at a stale position.
    func refreshWindowRect() {
        guard state == .starting || state == .recording,
              let rect = windowRect else { return }
        if let r = rect() {
            fl_drm_view_recording_set_window_rect(Int32(r.0), Int32(r.1),
                                                  Int32(r.2), Int32(r.3))
        } else {
            fl_drm_view_recording_set_window_rect(0, 0, 0, 0)
        }
    }

    func stop() { endSession(reason: nil) }

    /// Stop with a failure `reason` (nil = normal stop, keep the file).
    private func endSession(reason: String?) {
        guard state == .starting || state == .recording else { return }
        state = .stopping
        // Drop the zoom before the engine tears the session down, so the
        // next recording never inherits the last one's crop.
        zoomSupported = false
        zoomLevel = 1.0; zoomTarget = 1.0
        center = (0.5, 0.5); centerTarget = (0.5, 0.5)
        onChange?()
        fl_drm_view_recording_stop(drmViewHandle)
        pacer?.cancel()
        pacer = nil

        let enc = encoder
        encoder = nil
        let zenc = vaapiEncoder
        vaapiEncoder = nil
        let failure = reason
        let work: () -> Void = { [weak self] in
            // The engine joins its writer thread when it consumes the stop
            // (recording_active drops); after that no ingest can be running.
            // The pump keeps presents flowing while we wait. Cap the wait —
            // a VT switch mid-stop could park presents indefinitely.
            var waitedMs = 0
            while fl_drm_view_recording_active() != 0 && waitedMs < 3000 {
                usleep(50_000)
                waitedMs += 50
            }
            // Zero-copy: frames queued after the encoder was detached only
            // need their ring slots back (the footage ends at the stop).
            if let self {
                self.dmabufLock.lock()
                let leftovers = self.dmabufPending
                self.dmabufPending.removeAll()
                self.dmabufLock.unlock()
                for f in leftovers {
                    fl_drm_view_recording_release_dmabuf_slot(f.slot)
                }
            }
            var saved: String? = nil
            var detail = failure ?? ""
            if let zenc {
                if failure == nil, zenc.finish() {
                    saved = zenc.outputURL.path
                    Self.chownToLoginUser(zenc.outputURL.path)
                } else {
                    if failure == nil {
                        detail = zenc.frameCount == 0
                            ? "no frames were captured"
                            : "hardware encode failed: \(zenc.errorOutput)"
                    }
                    zenc.abort()
                }
            } else if let enc {
                if failure == nil, enc.finish() {
                    saved = enc.outputURL.path
                    Self.chownToLoginUser(enc.outputURL.path)
                } else {
                    if failure == nil {
                        detail = enc.frameCount == 0
                            ? "no frames were captured"
                            : "ffmpeg failed: \(enc.errorOutput)"
                    }
                    enc.abort()
                }
            }
            let finish: () -> Void = { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.startedAt = nil
                self.windowAlive = nil
                self.windowRect = nil
                self.windowLabel = nil
                self.sessionURL = nil
                Self.recordedTextureId = -1
                if saved != nil { self.lastSavedPath = saved }
                self.onChange?()
                self.onFinished?(saved, detail)
            }
            DispatchQueue.main.async(
                execute: unsafeBitCast(finish, to: (@Sendable () -> Void).self))
        }
        queue.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }

    // MARK: Pacing (pacer queue)

    private func startPacer(deadline: Date) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(33),
                       repeating: .nanoseconds(1_000_000_000 / Self.fps))
        timer.setEventHandler { [weak self] in
            self?.pacerTick(startDeadline: deadline)
        }
        timer.resume()
        pacer = timer
    }

    private func pacerTick(startDeadline: Date) {
        guard let enc = encoder else { return }

        mailboxLock.lock()
        let have = mailboxFresh
        if have {
            if scratch.count != mailbox.count { scratch = mailbox }
            else {
                scratch.withUnsafeMutableBytes { dst in
                    mailbox.withUnsafeBytes { src in
                        memcpy(dst.baseAddress!, src.baseAddress!, src.count)
                    }
                }
            }
        }
        let mw = mailboxW, mh = mailboxH
        mailboxLock.unlock()

        guard have else {
            // Engine never delivered a first frame (callback unset, ES3
            // missing) — fail rather than sit in .starting forever.
            if Date() > startDeadline {
                hopToMain { $0.endSession(reason: "the engine delivered no frames") }
            }
            return
        }
        // A display mode switch mid-recording changes the frame size; the
        // encoder is fixed-size, so hold the last good frame (the pacer
        // repeats it) rather than feed ffmpeg garbage.
        guard mw == enc.width, mh == enc.height else { return }

        let ok = scratch.withUnsafeBytes { enc.appendFrame($0) }
        if !ok {
            hopToMain { $0.endSession(reason: "ffmpeg exited mid-recording") }
            return
        }
        if enc.frameCount == 1 {
            hopToMain {
                guard $0.state == .starting else { return }
                $0.state = .recording
                $0.onChange?()
            }
        }
    }

    private func hopToMain(_ body: @escaping (RecordingService) -> Void) {
        let run: () -> Void = { [weak self] in
            guard let self else { return }
            body(self)
        }
        DispatchQueue.main.async(
            execute: unsafeBitCast(run, to: (@Sendable () -> Void).self))
    }

    // MARK: Root-mode ownership

    /// Dev mode runs the shell as root; a recording the login user cannot
    /// open or delete is a bug. No-ops unprivileged.
    private static func chownToLoginUser(_ path: String) {
        guard getuid() == 0 else { return }
        if let pw = getpwuid(LoginUser.uid) {
            chown(path, pw.pointee.pw_uid, pw.pointee.pw_gid)
        }
    }

    private static func ensureOwnedDir(_ dir: URL) {
        let existed = FileManager.default.fileExists(atPath: dir.path)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        if !existed { chownToLoginUser(dir.path) }
    }
}

#endif
