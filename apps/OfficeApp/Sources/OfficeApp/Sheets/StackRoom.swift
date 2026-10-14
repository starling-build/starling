// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// How much stack a recursion has left. A LAMBDA that calls itself stops at
// Excel's limit of 1024 calls, which fits Linux's and macOS's 8 MB main
// thread with room to spare — and overflows Windows' 1 MB one, so a
// runaway =FOREVER(1) took the app down there instead of giving #NUM!.
// Its own file so that WinSDK's names stay out of the engine's.

#if os(Windows)
import WinSDK
#endif

enum StackRoom {
    /// True when this thread is within `margin` bytes of the end of its
    /// stack. Only Windows says; elsewhere the depth limit is enough.
    static func low(margin: UInt = 192 * 1024) -> Bool {
        #if os(Windows)
        var lo: ULONG_PTR = 0, hi: ULONG_PTR = 0
        GetCurrentThreadStackLimits(&lo, &hi)
        var here = 0
        let sp = withUnsafeMutablePointer(to: &here) { UInt(bitPattern: $0) }
        return sp < UInt(lo) + margin
        #else
        return false
        #endif
    }
}
