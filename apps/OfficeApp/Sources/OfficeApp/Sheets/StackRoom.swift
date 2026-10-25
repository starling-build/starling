// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// How much stack a recursion has left. A LAMBDA that calls itself stops at
// Excel's limit of 1024 calls can exceed the native thread's stack,
// especially with an unoptimized evaluator. A runaway =FOREVER(1)
// must give #NUM! instead of taking the app down.
// Its own file so that WinSDK's names stay out of the engine's.

#if os(Windows)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#endif

enum StackRoom {
    /// True when this thread is within `margin` bytes of the end of its
    /// stack on Windows and Darwin. Elsewhere the depth limit applies.
    static func low(margin: UInt = 192 * 1024) -> Bool {
        #if os(Windows)
        var lo: ULONG_PTR = 0, hi: ULONG_PTR = 0
        GetCurrentThreadStackLimits(&lo, &hi)
        var here = 0
        let sp = withUnsafeMutablePointer(to: &here) { UInt(bitPattern: $0) }
        return sp < UInt(lo) + margin
        #elseif canImport(Darwin)
        let thread = pthread_self()
        let hi = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        var here = 0
        let sp = withUnsafeMutablePointer(to: &here) { UInt(bitPattern: $0) }
        return sp < hi - size + margin
        #else
        return false
        #endif
    }
}
