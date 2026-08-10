// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import StarlingRecord

#if os(Linux)
import Glibc

/// Plays a looping aerial clip for the screensaver: one spawned ffmpeg per
/// run, raw RGBA down a pipe, frames published to a mailbox the shell drains
/// on the main thread.
///
/// Nothing here links FFmpeg — the process boundary is deliberate, exactly as
/// in VideoPlayerApp's PipeDecoder (the linked decoder was dropped in ade2f64
/// for the GPL it dragged in; the .deb already Recommends the ffmpeg binary
/// for the screen recorder). That constraint is what shapes everything below:
/// we can choose ffmpeg's *arguments* freely, but we cannot hand ourselves a
/// decoded surface, so the frame has to come back as bytes.
///
/// **Decode, scale and colour conversion all happen on the GPU when VAAPI can
/// do them.** `scale_vaapi` cover-scales the decoded surface and converts it
/// to RGBA before `hwdownload`, so the CPU never touches a YUV plane and
/// swscale is out of the loop entirely. Measured on the dev box, 10s of a
/// 2560x1600 H.264 clip:
///
///     CPU decode + CPU scale + CPU rgba   11.8s of CPU   (what this used to do)
///     VAAPI decode + scale + csc          3.8s of CPU    (3.1x less)
///
/// The wire format is identical — packed RGBA at exactly the shown size — so
/// this is a change of ffmpeg arguments, not of the protocol.
///
/// What is still NOT zero-copy: the download itself, and the upload into
/// glTexImage2D on the far side. Removing those needs the decoder to hand the
/// compositor a dma-buf — and the way to do that is already in the tree.
/// VideoPlayerApp's `CH264Decoder` decodes H.264 into a dma-buf with its own
/// MP4 demuxer and its own bitstream parsing, over libva directly, which is
/// MIT. No GPL question, no spawned process. Pointing the screensaver at it
/// is the remaining work; see docs/plans/screensaver.md.
///
/// Pacing is the READER's job: the pipe is forced to exact CFR, so holding the
/// reader to one frame per interval IS holding playback to real time.
final class AerialPlayer: @unchecked Sendable {

    let width: Int
    let height: Int
    let fps: Double

    private let clip: String
    private let ffmpeg: String

    // Everything mutable is guarded — `stop()` runs on the main thread while
    // the decode thread is mid-spawn or mid-read.
    private let lock = NSLock()
    private var process: Process?
    private var out: Pipe?
    private var stopped = false
    private var mailbox: UnsafeMutableRawPointer?
    private var mailboxFilled = false

    private var thread: Thread?

    private static func findTool(_ tool: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/\(tool)") {
            return "/usr/bin/\(tool)"
        }
        for dir in (env["PATH"] ?? "").split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// The first playable clip: `STARLING_AERIAL` (a file or a directory),
    /// else an `aerials/` directory beside the wallpapers, else
    /// ~/.local/share/starling/aerials. Nil means "no aerials installed" —
    /// the screensaver falls back to the liquid warp, which needs no assets.
    static func discoverClip() -> String? {
        let fm = FileManager.default
        var dirs: [String] = []
        if let env = ProcessInfo.processInfo.environment["STARLING_AERIAL"],
           !env.isEmpty {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: env, isDirectory: &isDir) {
                if !isDir.boolValue { return env }
                dirs.append(env)
            }
        }
        if let packaged = _DesktopShellState.dataFilePath("aerials") {
            dirs.append(packaged)
        }
        dirs.append(LoginUser.home + "/.local/share/starling/aerials")

        let exts = ["mp4", "mov", "m4v", "webm", "mkv"]
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            let clips = names
                .filter { exts.contains(($0 as NSString).pathExtension.lowercased()) }
                .sorted()
            if let first = clips.first { return dir + "/" + first }
        }
        return nil
    }

    /// The render node for the card the compositor is on, matched through the
    /// sysfs device links exactly as `find_render_node_devid()` does in
    /// wayland_dmabuf.c. Picking a node by number is not good enough on a
    /// two-GPU laptop: this one's renderD128 is the nouveau device, whose
    /// VAAPI fails to initialise, while the compositor is on renderD129.
    ///
    /// Nil means "no confident match" — the caller decodes on the CPU rather
    /// than guessing a node, because a wrong node is a failed spawn.
    private static func compositorRenderNode() -> String? {
        // One implementation, in StarlingRecord — the recorder needs the same
        // answer for the same reason, and the two drifted: this one matched
        // through sysfs while the encoder picked whatever node sorted first
        // and could encode, which is a different card the moment both GPUs
        // can. Keep it shared so there is nothing left to disagree about.
        VaapiEncoder.compositorRenderNode()
    }

    /// The clip's coded size, so a cropdetect result can be told apart from
    /// "no bars at all". Nil when ffprobe is unavailable or says nothing
    /// useful — treated as "assume bars", which keeps the CPU path.
    private static func probeSize(clip: String) -> (Int, Int)? {
        guard let ffprobe = findTool("ffprobe") else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffprobe)
        p.arguments = [
            "-v", "error", "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x", clip,
        ]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let parts = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "x").compactMap { Int($0) } ?? []
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return (parts[0], parts[1])
    }

    /// Letterbox bars are real content in the file, and a cover-crop to the
    /// panel aspect crops width — so bars would survive it. cropdetect finds
    /// the active rectangle first. Returns nil if it can't tell (then the
    /// filter chain just cover-crops the whole frame).
    ///
    /// ~0.4s of decoding on the dev box, which is why this runs on the decode
    /// thread: it used to block the main thread inside `init`, stalling more
    /// than half of the screensaver's own 700ms fade-in.
    private static func detectActiveRect(clip: String, ffmpeg: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = [
            "-hide_banner", "-ss", "5", "-i", clip,
            "-vf", "cropdetect=24:2:0", "-frames:v", "40", "-f", "null", "-",
        ]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Last "crop=W:H:X:Y" wins — cropdetect converges as it sees frames.
        var found: String?
        for line in text.split(separator: "\n") {
            guard let r = line.range(of: "crop=") else { continue }
            let tail = line[r.upperBound...]
            let spec = tail.prefix { $0.isNumber || $0 == ":" }
            if spec.split(separator: ":").count == 4 { found = String(spec) }
        }
        return found
    }

    /// Config only — no subprocess. Everything that costs time (the cropdetect
    /// probe, the ffprobe, the decoder spawn) happens on the decode thread in
    /// `start()`, because this is constructed from `_activateScreensaver` on
    /// the main thread while the fade is running.
    init?(clip: String, width: Int, height: Int, fps: Double = 24.0) {
        guard let ffmpeg = Self.findTool("ffmpeg") else { return nil }
        self.ffmpeg = ffmpeg
        self.clip = clip
        self.width = max(2, width & ~1)
        self.height = max(2, height & ~1)
        self.fps = min(60, max(1, fps))

        signal(SIGPIPE, SIG_IGN)
        mailbox = UnsafeMutableRawPointer.allocate(
            byteCount: self.width * self.height * 4,
            alignment: MemoryLayout<UInt8>.alignment)
    }

    func start() {
        let t = Thread { [weak self] in self?.decodeLoop() }
        t.name = "aerial decode"
        t.stackSize = 512 * 1024
        thread = t
        t.start()
    }

    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    // ── Decoding ─────────────────────────────────────────────────────────

    /// Arguments for the GPU chain: VAAPI decode, cover-scale and RGBA
    /// conversion on the GPU, download last. `fps` sits before `hwdownload`
    /// so a high-frame-rate source drops its extra frames before they cross
    /// the bus rather than after.
    ///
    /// `scale_vaapi` cannot crop, so this is only usable when there is no
    /// letterbox to strip: cropping after the scale would be the wrong
    /// geometry, and cropping before it means scaling on the CPU anyway.
    private func gpuArgs(node: String) -> [String] {
        [
            "-hide_banner", "-loglevel", "error",
            "-hwaccel", "vaapi", "-hwaccel_device", node,
            "-hwaccel_output_format", "vaapi",
            "-stream_loop", "-1",
            "-i", clip,
            "-vf", String(format:
                "fps=%.4f,scale_vaapi=w=%d:h=%d:force_original_aspect_ratio=increase"
                + ":format=rgba,hwdownload,format=rgba,crop=%d:%d",
                fps, width, height, width, height),
            "-f", "rawvideo", "-pix_fmt", "rgba", "-an",
            "pipe:1",
        ]
    }

    /// The all-CPU chain, unchanged: works everywhere, including where there
    /// is no VAAPI at all and where a clip has bars to strip.
    private func cpuArgs(activeRect: String?) -> [String] {
        var filters: [String] = []
        if let activeRect { filters.append("crop=\(activeRect)") }
        filters.append(
            "scale=\(width):\(height):force_original_aspect_ratio=increase")
        filters.append("crop=\(width):\(height)")
        // Exact CFR at the rate the reader paces — without it the rawvideo
        // muxer picks its own and playback runs fast or frozen-slow.
        filters.append(String(format: "fps=%.4f", fps))
        return [
            "-hide_banner", "-loglevel", "error",
            "-stream_loop", "-1",          // loop forever; the saver may run for hours
            "-i", clip,
            "-vf", filters.joined(separator: ","),
            "-f", "rawvideo", "-pix_fmt", "rgba", "-an",
            "pipe:1",
        ]
    }

    /// Try each decode mode in turn, falling through when one fails to
    /// deliver a single frame. That is the VAAPI probe: rather than paying a
    /// startup roundtrip to ask whether the driver can do this, spawn it and
    /// notice. A driver that refuses exits immediately, so the fallback costs
    /// a fraction of a second and only on machines that need it.
    private func decodeLoop() {
        let activeRect = Self.detectActiveRect(clip: clip, ffmpeg: ffmpeg)
        if isStopped() { return }

        // A cropdetect result equal to the whole frame is not a letterbox —
        // it is cropdetect saying "nothing to strip". Only a real inset rect
        // rules out the GPU chain.
        var hasBars = activeRect != nil
        if let activeRect, let (sw, sh) = Self.probeSize(clip: clip) {
            hasBars = activeRect != "\(sw):\(sh):0:0"
        }
        if isStopped() { return }

        let vaapiWanted =
            ProcessInfo.processInfo.environment["STARLING_AERIAL_VAAPI"] != "0"

        var attempts: [(label: String, args: [String])] = []
        if vaapiWanted, !hasBars, let node = Self.compositorRenderNode() {
            attempts.append(("vaapi \(node)", gpuArgs(node: node)))
        }
        attempts.append(("cpu", cpuArgs(activeRect: hasBars ? activeRect : nil)))

        for attempt in attempts {
            if isStopped() { return }
            guard spawn(args: attempt.args) else { continue }
            let delivered = readFrames()
            reapProcess()
            if delivered > 0 || isStopped() {
                return   // played (until stop), or asked to quit
            }
            FileHandle.standardError.write(Data(
                ("[AerialPlayer] \(attempt.label) decode produced no frames"
                 + " — falling back\n").utf8))
        }
        FileHandle.standardError.write(Data(
            "[AerialPlayer] no usable decode path — staying on the warp\n".utf8))
    }

    private func spawn(args: [String]) -> Bool {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice

        lock.lock()
        if stopped { lock.unlock(); return false }
        guard (try? p.run()) != nil else { lock.unlock(); return false }
        process = p
        out = pipe
        lock.unlock()
        return true
    }

    /// Read whole frames until the pipe ends. Returns how many were
    /// delivered, which is how the caller tells "this decoder works" from
    /// "this decoder refused".
    private func readFrames() -> Int {
        lock.lock()
        let pipe = out
        lock.unlock()
        guard let pipe else { return 0 }

        let frameBytes = width * height * 4
        var buffer = [UInt8](repeating: 0, count: frameBytes)
        let fd = pipe.fileHandleForReading.fileDescriptor
        let interval = 1.0 / fps
        var next = Date().timeIntervalSinceReferenceDate
        var delivered = 0

        while !isStopped() {
            var got = 0
            let ok: Bool = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                while got < frameBytes {
                    let n = read(fd, base + got, frameBytes - got)
                    if n > 0 {
                        got += n
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        return false  // EOF, a refused decoder, or stop()
                    }
                }
                return true
            }
            guard ok, !isStopped() else { break }

            lock.lock()
            if let box = mailbox {
                buffer.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        box.copyMemory(from: base, byteCount: frameBytes)
                    }
                }
                mailboxFilled = true
            }
            lock.unlock()
            delivered += 1

            next += interval
            let now = Date().timeIntervalSinceReferenceDate
            if next > now {
                usleep(UInt32((next - now) * 1_000_000))
            } else {
                next = now  // fell behind (a slow upload); don't sprint to catch up
            }
        }
        return delivered
    }

    /// Kill and reap whichever decoder is running, leaving no process and no
    /// pipe behind for the next attempt.
    private func reapProcess() {
        lock.lock()
        let p = process
        let pipe = out
        process = nil
        out = nil
        lock.unlock()

        if let p, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        try? pipe?.fileHandleForReading.close()
        p?.waitUntilExit()
    }

    /// Hand the newest decoded frame to `body`, or do nothing if none has
    /// arrived since the last drain. Main thread only.
    func withNewFrame(_ body: (UnsafeRawPointer, Int, Int) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard mailboxFilled, let box = mailbox else { return }
        mailboxFilled = false
        body(box, width, height)
    }

    /// Kill the decode run. Safe from the main thread and more than once.
    ///
    /// Deliberately does NOT wait for the decode thread: this is called from
    /// the screensaver's teardown, on the main thread, while the wake
    /// animation runs — and the thread can be inside the ~0.4s cropdetect
    /// probe, which would stall exactly the frames the user is watching. It
    /// signals and returns; the thread notices `stopped` and unwinds on its
    /// own.
    ///
    /// The mailbox is therefore freed in `deinit`, not here. That is safe
    /// without any join: the decode thread's closure resolves `self?` into a
    /// strong reference for the whole of `decodeLoop`, so deinit cannot run
    /// while a read is in flight.
    func stop() {
        lock.lock()
        stopped = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    deinit {
        lock.lock()
        stopped = true
        let p = process
        let pipe = out
        process = nil
        out = nil
        mailbox?.deallocate()
        mailbox = nil
        mailboxFilled = false
        lock.unlock()
        if let p, p.isRunning { kill(p.processIdentifier, SIGKILL) }
        try? pipe?.fileHandleForReading.close()
    }
}

#endif
