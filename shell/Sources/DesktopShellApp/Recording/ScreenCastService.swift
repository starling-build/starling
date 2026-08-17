// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterDRMBridge
import PipeWireCast
import PortalService
import StarlingRecord

/// Portal ScreenCast sessions: the engine's CPU capture sink feeding a
/// PipeWire video-source stream that portal clients (Chromium, OBS,
/// gstreamer) consume. The app-facing sibling of RecordingService — same
/// capture pipeline, but frames leave as a live stream instead of an
/// encoded file.
///
/// The engine runs ONE capture session, so casting and recording are
/// mutually exclusive: each side checks the other before starting
/// (RecordingService.start refuses while `captureActive`; startSession
/// refuses while `recording_active()`), and main.swift's frame trampoline
/// routes each frame to whichever service owns the session.
///
/// Threads: startSession/stopSession run on the PORTAL thread, ingest on
/// the engine's recorder writer thread, pumpTick on the main queue. All
/// state lives behind one lock; the pw stream calls take their own loop
/// lock internally and never call back into us.
final class ScreenCastService {

    /// Frame routing for main.swift's trampoline: true from the moment a
    /// cast session claims the capture until its drain completes.
    nonisolated(unsafe) private(set) static var captureActive = false

    /// Completes the portal's async Start (set at wiring time to
    /// PortalIntegration.completeScreenCastStart). Thread-safe target.
    var completeStart: ((_ handle: String, _ node: UInt32,
                         _ width: UInt32, _ height: UInt32,
                         _ response: UInt32) -> Void)?

    private enum State {
        case idle
        case starting(handle: String)  // engine capture requested, no frame yet
        case live                      // stream up, frames flowing
        case draining                  // stop requested, waiting for the engine
    }

    private let lock = NSLock()
    private var state: State = .idle
    private var cast: OpaquePointer?   // PwCast*
    private var generation = 0

    /// True while the frame-tick pump must run: presents carry the
    /// engine's start/stop requests and deliver the frames themselves.
    var needsFramePump: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .idle = state { return false }
        return true
    }

    /// True while the capture pipeline is priming. The engine's PBO ring
    /// completes a readback only a few presents after its blit, so at the
    /// pump's floor rate (~4 presents/s) the first frame would take
    /// seconds to surface and the portal Start would time out — the pump
    /// runs full-rate rebuilds until the first frame lands. (Recording
    /// never sees this: the record tile's own UI churn primes the ring.)
    var needsPrimingRebuilds: Bool {
        lock.lock(); defer { lock.unlock() }
        if case .starting = state { return true }
        return false
    }

    // MARK: Session control (portal thread)

    /// Start hook: claim the capture and request engine frames. The
    /// stream itself is stood up when the first frame arrives (its size
    /// is the negotiated size — no duplicating the engine's shift math).
    /// Returns 0 if under way, -1 to fail the portal request.
    func startSession(handle: String) -> Int32 {
        guard let view = drmViewHandle else { return -1 }
        guard pwcast_available() != 0 else {
            FileHandle.standardError.write(
                Data("[ScreenCast] no PipeWire daemon socket\n".utf8))
            return -1
        }
        guard fl_drm_view_recording_active() == 0 else { return -1 }
        // The engine's one capture session may already belong to RDP.
        guard !RdpService.captureActive else {
            FileHandle.standardError.write(
                Data("[ScreenCast] a remote desktop client owns the capture\n".utf8))
            return -1
        }

        lock.lock()
        guard case .idle = state else { lock.unlock(); return -1 }
        state = .starting(handle: handle)
        generation += 1
        let gen = generation
        Self.captureActive = true
        lock.unlock()

        // Same policy as the software recording path: full screen, GPU
        // downscale for panels too big to shepherd through the CPU.
        let w = Int(fl_drm_view_get_width(view))
        let h = Int(fl_drm_view_get_height(view))
        let shift = FfmpegEncoder.downscaleShift(width: w, height: h,
                                                 hardware: false)
        fl_drm_view_recording_set_dmabuf(0)
        fl_drm_view_recording_start(view, Int32(shift))

        // If the engine never feeds us (a recording won the start race, no
        // presents), fail the portal request instead of hanging the client.
        let deadline: () -> Void = { [weak self] in
            self?.failIfStillStarting(generation: gen)
        }
        DispatchQueue.global().asyncAfter(
            deadline: .now() + 3,
            execute: unsafeBitCast(deadline, to: (@Sendable () -> Void).self))
        return 0
    }

    /// Stop hook (session closed or replaced). Requests the engine stop;
    /// pumpTick observes the drain finishing and frees the stream. Frames
    /// that arrive meanwhile still route here (captureActive stays true)
    /// and are dropped, rather than leaking into the recording mailbox.
    func stopSession() {
        lock.lock()
        switch state {
        case .idle, .draining:
            lock.unlock()
        case .starting, .live:
            state = .draining
            lock.unlock()
            fl_drm_view_recording_stop(drmViewHandle)
        }
    }

    private func failIfStillStarting(generation gen: Int) {
        lock.lock()
        guard generation == gen, case .starting(let handle) = state else {
            lock.unlock()
            return
        }
        state = .draining
        lock.unlock()
        FileHandle.standardError.write(
            Data("[ScreenCast] engine delivered no frames — failing Start\n".utf8))
        fl_drm_view_recording_stop(drmViewHandle)
        completeStart?(handle, 0, 0, 0, 2)
    }

    // MARK: Frames (engine recorder writer thread)

    /// One top-down RGBA frame. First frame stands up the PipeWire stream
    /// and completes the portal Start; the rest push straight through.
    func ingest(_ rgba: UnsafePointer<UInt8>?, width: Int, height: Int) {
        guard let rgba, width > 0, height > 0 else { return }
        lock.lock()
        switch state {
        case .starting(let handle):
            guard let c = pwcast_start(UInt32(width), UInt32(height)) else {
                state = .draining
                lock.unlock()
                fl_drm_view_recording_stop(drmViewHandle)
                completeStart?(handle, 0, 0, 0, 2)
                return
            }
            cast = c
            state = .live
            let node = pwcast_node_id(c)
            lock.unlock()
            completeStart?(handle, node, UInt32(width), UInt32(height), 0)
            pwcast_push_frame(c, rgba, UInt32(width), UInt32(height))
        case .live:
            let c = cast
            lock.unlock()
            pwcast_push_frame(c, rgba, UInt32(width), UInt32(height))
        case .idle, .draining:
            lock.unlock()
        }
    }

    // MARK: Pump (main queue, every tick while needsFramePump)

    /// Rides the frame-tick pump like checkWindowAlive: once the engine
    /// confirms the stop drained, release the capture and the stream.
    func pumpTick() {
        lock.lock()
        guard case .draining = state,
              fl_drm_view_recording_active() == 0 else {
            lock.unlock()
            return
        }
        let c = cast
        cast = nil
        state = .idle
        Self.captureActive = false
        lock.unlock()
        if let c { pwcast_stop(c) }
    }
}

// MARK: - Portal thunks (portal thread)

/// C-ABI hooks registered with the portal service, reaching the service
/// through the global — the same shape as portalChooserLaunchThunk.
let portalScreenCastStartThunk: portal_screencast_start_fn = { _, handle in
    guard let handle, let svc = screenCastService else { return -1 }
    return svc.startSession(handle: String(cString: handle))
}

let portalScreenCastStopThunk: portal_screencast_stop_fn = { _ in
    screenCastService?.stopSession()
}

#endif
