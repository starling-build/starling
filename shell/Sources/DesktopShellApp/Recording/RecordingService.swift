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
        FfmpegEncoder.findFfmpeg() != nil || resolveZeroCopyKind() != nil

    // Probe results — real test opens, run once. Warmed in the background
    // at init so the first Record tap doesn't pay for them; the lock makes
    // a too-early tap wait instead of racing.
    private let hwLock = NSLock()
    private var hwProbed = false
    private var hwEncoder: HardwareEncoder?
    private var zcProbed = false
    private var zcKind: ZeroCopyKind?

    /// Which in-process encoder a zero-copy session opens: whichever API
    /// belongs to the GPU that renders the recorded frames.
    private enum ZeroCopyKind {
        case vaapi(device: String)
        case nvenc
    }

    /// Driver behind a DRM node ("amdgpu", "nvidia", …), from sysfs.
    private static func drmDriverName(forNode node: String) -> String? {
        let name = (node as NSString).lastPathComponent
        guard let link = try? FileManager.default.destinationOfSymbolicLink(
            atPath: "/sys/class/drm/\(name)/device/driver") else { return nil }
        return (link as NSString).lastPathComponent
    }

    init() {
        let warm: () -> Void = { [weak self] in
            _ = self?.resolveZeroCopyKind()
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

    /// The in-process encode path sessions will use, or nil. When this
    /// resolves, sessions record in-process: dmabuf frames, GPU encode, no
    /// ffmpeg child, no pacer.
    ///
    /// Recording never crosses GPUs: a screen is encoded by the GPU that
    /// renders it, so the encoder follows the compositor's device — NVENC
    /// when the frames the ring will hand us are NVIDIA-resident, VAAPI
    /// otherwise. Today the one engine device renders every view; when
    /// views get per-device rendering, this resolves per recorded view.
    private func resolveZeroCopyKind() -> ZeroCopyKind? {
        hwLock.lock()
        defer { hwLock.unlock() }
        if !zcProbed {
            if Self.drmDriverName(forNode:
                ProcessInfo.processInfo.environment["FLUTTER_DRM_DEVICE"]
                    ?? "/dev/dri/card0") == "nvidia",
               NvencEncoder.available() {
                zcKind = .nvenc
            } else if let device = VaapiEncoder.detectDevice() {
                zcKind = .vaapi(device: device)
            } else {
                zcKind = nil
            }
            zcProbed = true
            let msg: String
            switch zcKind {
            case .nvenc: msg = "[Recording] zero-copy NVENC encoder ready\n"
            case .vaapi: msg = "[Recording] zero-copy VAAPI encoder ready\n"
            case nil: msg = "[Recording] no zero-copy encoder — pipe path\n"
            }
            _ = msg.withCString { write(2, $0, strlen($0)) }
        }
        return zcKind
    }

    /// What the last (or current) session captures at, and through which
    /// encoder — the broker reports these so tests assert the file against
    /// the shell's own claim rather than re-deriving the policy.
    private(set) var captureWidth = 0
    private(set) var captureHeight = 0
    private(set) var usingHardware = false
    private(set) var zeroCopy = false
    /// Which encoder the session opened: "nvenc", "vaapi", "vaapi-pipe" or
    /// "x264" — the broker reports it so tests can assert the path taken.
    private(set) var encoderName = ""
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
    private var zcEncoder: (any InProcessEncoder)?
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
            guard let enc = zcEncoder else {
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
        zcEncoder?.abort()
        zcEncoder = nil
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
        guard let view = drmViewHandle else {
            onFinished?(nil, "no display")
            return
        }
        let ffmpeg = FfmpegEncoder.findFfmpeg()
        guard ffmpeg != nil || resolveZeroCopyKind() != nil else {
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
        var zc: (any InProcessEncoder)? = nil
        switch resolveZeroCopyKind() {
        case .vaapi(let device):
            zc = VaapiEncoder(device: device, inWidth: w, inHeight: h,
                              width: max(2, w & ~1),
                              height: max(2, h & ~1),
                              fps: Self.fps, outputURL: url)
        case .nvenc:
            zc = NvencEncoder(inWidth: w, inHeight: h,
                              width: max(2, w & ~1),
                              height: max(2, h & ~1),
                              fps: Self.fps, outputURL: url)
        case nil:
            break
        }
        if let zc {
            // In-process: full resolution always (the GPU encodes it for
            // free, and the transport is free too — that is the point).
            zcEncoder = zc
            encoder = nil
            zeroCopy = true
            usingHardware = true
            captureWidth = zc.width
            captureHeight = zc.height
            encoderName = zc is NvencEncoder ? "nvenc" : "vaapi"
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
            zcEncoder = nil
            zeroCopy = false
            usingHardware = hw != nil
            captureWidth = cw
            captureHeight = ch
            encoderName = hw != nil ? "vaapi-pipe" : "x264"
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
        onChange?()
        fl_drm_view_recording_stop(drmViewHandle)
        pacer?.cancel()
        pacer = nil

        let enc = encoder
        encoder = nil
        let zenc = zcEncoder
        zcEncoder = nil
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
