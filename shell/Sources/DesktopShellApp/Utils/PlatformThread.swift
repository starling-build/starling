// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterDRMBridge

/// Run `work` on the FRAMEWORK'S thread — the engine platform thread, the
/// epoll loop `fl_drm_view_run` spawns, where every build, every `setState`
/// and every callback that touches shell state runs.
///
/// NOT `DispatchQueue.main`. The process's main thread does nothing but run
/// Foundation's RunLoop (main.swift's last line), so a main-queue hop lands on
/// a thread the framework never uses, and a `setState` from there races
/// whatever build is in progress on the platform thread. That race is real
/// and was caught in a core dump: the icon decodes' completions mutated
/// `iconTextures` on the main thread while `initState` was still iterating
/// it on the platform thread — a general protection fault on roughly every
/// other launch once there were 74 guest-app icons to decode — and the
/// seamless reconcile's `addWindow` landing mid-build is what made
/// `_buildDock` see two different app lists in one frame.
///
/// `fl_drm_view_post_task` is the door; it runs the closure on the loop's
/// next iteration. Before the view exists, or on the non-DRM dev paths, the
/// main queue is all there is — and there is no concurrent build to race.
func onPlatformThread(_ work: @escaping () -> Void) {
    guard let view = drmViewHandle else {
        DispatchQueue.main.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
        return
    }
    let box = Unmanaged.passRetained(PlatformTask(work)).toOpaque()
    if fl_drm_view_post_task(view, { raw in
        Unmanaged<PlatformTask>.fromOpaque(raw!).takeRetainedValue().work()
    }, box) == 0 {
        Unmanaged<PlatformTask>.fromOpaque(box).release()
        FileHandle.standardError.write(Data(
            "[platform] post_task refused; running on the main queue\n".utf8))
        DispatchQueue.main.async(execute: unsafeBitCast(work, to: (@Sendable () -> Void).self))
    }
}

/// The same, after a delay. The work item is returned so the caller can
/// cancel it: cancellation is honoured before the hop and, by the item
/// itself, when it runs.
@discardableResult
func onPlatformThread(after seconds: Double, execute item: DispatchWorkItem) -> DispatchWorkItem {
    let hop: () -> Void = {
        guard !item.isCancelled else { return }
        onPlatformThread { item.perform() }
    }
    DispatchQueue.global().asyncAfter(
        deadline: .now() + seconds,
        execute: unsafeBitCast(hop, to: (@Sendable () -> Void).self))
    return item
}

@discardableResult
func onPlatformThread(after seconds: Double, _ work: @escaping () -> Void) -> DispatchWorkItem {
    onPlatformThread(after: seconds, execute: DispatchWorkItem(block: work))
}

private final class PlatformTask {
    let work: () -> Void
    init(_ work: @escaping () -> Void) { self.work = work }
}
#endif
