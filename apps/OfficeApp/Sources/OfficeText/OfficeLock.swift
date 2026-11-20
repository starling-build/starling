// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A lock for the text engine's few shared tables: one thread in the
/// browser, and no NSLock in its Foundation (see `OfficeFonts.declaredLock`).
#if os(WASI)
struct OfficeLock { func lock() {}; func unlock() {} }
#else
typealias OfficeLock = NSLock
#endif
