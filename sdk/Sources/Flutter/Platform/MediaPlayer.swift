// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One audio/video playback interface (like Flutter's video_player), backed by
// the platform media stack: GStreamer on Linux, AVFoundation on Apple
// platforms, the HTML video element on web. Poster frames are drawn by the
// caller and do not depend on any of this.

import Foundation
#if canImport(AVFoundation) && canImport(CoreGraphics) && !os(Linux)
import AVFoundation
import CoreGraphics
#endif

public enum MediaPlayerStatus: Equatable {
    case idle, loading, playing, paused, ended
    case failed(String)
}

/// One decoded video frame, tightly packed RGBA8888.
public struct MediaFrame {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int
}

public protocol MediaPlayer: AnyObject {
    var status: MediaPlayerStatus { get }
    /// Seconds; 0 until known.
    var position: Double { get }
    var duration: Double { get }
    /// 0...1.
    var volume: Double { get set }

    /// Starts loading `url` (file:// or http(s)://) and plays it.
    func open(url: String)
    func play()
    func pause()
    func stop()
    func seek(to seconds: Double)
    /// Drains pending events and returns the video frame that is due, if
    /// any. Call from the UI's frame timer; it never blocks.
    func pollFrame() -> MediaFrame?
}

/// A player for this platform, or nil when no backend is available (for
/// example GStreamer is not installed).
public func makeMediaPlayer() -> MediaPlayer? {
    #if os(Linux)
    return GStreamerPlayer()
    #elseif canImport(AVFoundation) && canImport(CoreVideo)
    return AVFoundationPlayer()
    #else
    return nil
    #endif
}

/// One still frame of a movie file, for a poster; blocks, so call it off the UI thread. Apple platforms ask
/// AVAssetImageGenerator, which is made for stills and needs no run loop; elsewhere a player is run until a
/// frame arrives. Nil when nothing can decode the file.
public func mediaFirstFrame(url: String) -> MediaFrame? {
    #if canImport(AVFoundation) && canImport(CoreGraphics) && !os(Linux)
    guard let u = URL(string: url) else { return nil }
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
    gen.appliesPreferredTrackTransform = true
    guard let image = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    let w = image.width, h = image.height
    guard w > 0, h > 0 else { return nil }
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let drawn = px.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    guard drawn else { return nil }
    for i in stride(from: 3, to: px.count, by: 4) { px[i] = 255 }
    return MediaFrame(pixels: px, width: w, height: h)
    #elseif os(WASI)
    return nil  // no player backend on web (and no Thread.sleep)
    #else
    guard let player = makeMediaPlayer() else { return nil }
    defer { player.stop() }
    player.volume = 0
    player.open(url: url)
    for _ in 0 ..< 60 {
        if let f = player.pollFrame() { return f }
        if case .failed = player.status { return nil }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
    #endif
}
