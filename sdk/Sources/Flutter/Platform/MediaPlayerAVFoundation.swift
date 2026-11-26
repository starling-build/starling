// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// AVFoundation backend for MediaPlayer (macOS, iOS). AVPlayer decodes and
// plays the audio; video frames come out of an AVPlayerItemVideoOutput as
// BGRA pixel buffers and are handed over as RGBA.

#if canImport(AVFoundation) && canImport(CoreVideo)
import AVFoundation
import CoreVideo
import Foundation

final class AVFoundationPlayer: MediaPlayer {
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var endObserver: NSObjectProtocol?
    private var wantPlaying = false
    private var _volume = 1.0
    private(set) var status: MediaPlayerStatus = .idle

    deinit { stop() }

    func open(url: String) {
        stop()
        guard let u = URL(string: url) else { status = .failed("bad url"); return }
        let item = AVPlayerItem(url: u)
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(out)
        let p = AVPlayer(playerItem: item)
        p.volume = Float(_volume)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: nil
        ) { [weak self] _ in self?.status = .ended }
        player = p
        output = out
        wantPlaying = true
        status = .loading
        p.play()
    }

    func play() {
        guard let p = player else { return }
        if status == .ended { seek(to: 0) }
        wantPlaying = true
        p.play()
        if status == .paused { status = .playing }
    }

    func pause() {
        guard let p = player else { return }
        wantPlaying = false
        p.pause()
        if status == .playing { status = .paused }
    }

    func stop() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        output = nil
        status = .idle
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        p.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
               toleranceBefore: .zero, toleranceAfter: .zero)
        if status == .ended { status = wantPlaying ? .playing : .paused; if wantPlaying { p.play() } }
    }

    var volume: Double {
        get { _volume }
        set { _volume = min(max(newValue, 0), 1); player?.volume = Float(_volume) }
    }

    var position: Double {
        guard let t = player?.currentTime(), t.isNumeric else { return 0 }
        return t.seconds
    }

    var duration: Double {
        guard let d = player?.currentItem?.duration, d.isNumeric else { return 0 }
        return d.seconds
    }

    func pollFrame() -> MediaFrame? {
        guard let p = player, let out = output, let item = p.currentItem else { return nil }
        switch item.status {
        case .failed: status = .failed(item.error?.localizedDescription ?? "playback error"); return nil
        case .readyToPlay: if status == .loading { status = wantPlaying ? .playing : .paused }
        default: break
        }
        let t = out.itemTime(forHostTime: CACurrentMediaTime())
        guard out.hasNewPixelBuffer(forItemTime: t),
              let buf = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) else { return nil }
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf)
        let stride = CVPixelBufferGetBytesPerRow(buf)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buf) else { return nil }
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let src = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<h {
            let row = src + y * stride
            for x in 0..<w {
                let s = row + x * 4, d = (y * w + x) * 4
                px[d] = s[2]; px[d + 1] = s[1]; px[d + 2] = s[0]; px[d + 3] = s[3]
            }
        }
        return MediaFrame(pixels: px, width: w, height: h)
    }
}
#endif
