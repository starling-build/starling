// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// GStreamer backend for MediaPlayer. The libraries are loaded with dlopen, so
// building needs no GStreamer headers and a machine without GStreamer just
// gets no player. Pull model: playbin decodes, video goes through
// videoconvert into an RGBA appsink with sync=true, and pollFrame() pulls
// with a zero timeout, so the sink paces display itself.

#if os(Linux)
import Foundation

private final class GstLib {
    static let shared: GstLib? = GstLib()

    typealias P = UnsafeMutableRawPointer
    let gstInit: @convention(c) (P?, P?) -> Void
    let factoryMake: @convention(c) (UnsafePointer<CChar>, P?) -> P?
    let parseBin: @convention(c) (UnsafePointer<CChar>, Int32, UnsafeMutablePointer<P?>) -> P?
    let binByName: @convention(c) (P, UnsafePointer<CChar>) -> P?
    let setState: @convention(c) (P, Int32) -> Int32
    let getBus: @convention(c) (P) -> P?
    let popFiltered: @convention(c) (P, UInt32) -> P?
    let miniUnref: @convention(c) (P) -> Void
    let objectUnref: @convention(c) (P) -> Void
    let parseError: @convention(c) (P, UnsafeMutablePointer<P?>, P?) -> Void
    let queryPosition: @convention(c) (P, Int32, UnsafeMutablePointer<Int64>) -> Int32
    let queryDuration: @convention(c) (P, Int32, UnsafeMutablePointer<Int64>) -> Int32
    let seekSimple: @convention(c) (P, Int32, UInt32, Int64) -> Int32
    let sampleCaps: @convention(c) (P) -> P?
    let sampleBuffer: @convention(c) (P) -> P?
    let capsStructure: @convention(c) (P, UInt32) -> P?
    let structureInt: @convention(c) (P, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32
    let bufferMap: @convention(c) (P, P, UInt32) -> Int32
    let bufferUnmap: @convention(c) (P, P) -> Void
    let appPull: @convention(c) (P, UInt64) -> P?
    let setProperty: @convention(c) (P, UnsafePointer<CChar>, P) -> Void
    let valueInit: @convention(c) (P, UInt) -> P?
    let valueSetString: @convention(c) (P, UnsafePointer<CChar>) -> Void
    let valueSetObject: @convention(c) (P, P?) -> Void
    let valueSetDouble: @convention(c) (P, Double) -> Void
    let valueUnset: @convention(c) (P) -> Void

    private init?() {
        func open(_ names: [String]) -> P? {
            for n in names { if let h = dlopen(n, RTLD_NOW | RTLD_GLOBAL) { return h } }
            return nil
        }
        guard let gst = open(["libgstreamer-1.0.so.0", "libgstreamer-1.0.so"]),
              let app = open(["libgstapp-1.0.so.0", "libgstapp-1.0.so"]),
              let gobj = open(["libgobject-2.0.so.0", "libgobject-2.0.so"]),
              let glib = open(["libglib-2.0.so.0", "libglib-2.0.so"]) else { return nil }
        _ = glib
        func sym<T>(_ h: P, _ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        guard
            let a = sym(gst, "gst_init", (@convention(c) (P?, P?) -> Void).self),
            let b = sym(gst, "gst_element_factory_make", (@convention(c) (UnsafePointer<CChar>, P?) -> P?).self),
            let c = sym(gst, "gst_parse_bin_from_description", (@convention(c) (UnsafePointer<CChar>, Int32, UnsafeMutablePointer<P?>) -> P?).self),
            let d = sym(gst, "gst_bin_get_by_name", (@convention(c) (P, UnsafePointer<CChar>) -> P?).self),
            let e = sym(gst, "gst_element_set_state", (@convention(c) (P, Int32) -> Int32).self),
            let f = sym(gst, "gst_element_get_bus", (@convention(c) (P) -> P?).self),
            let g = sym(gst, "gst_bus_pop_filtered", (@convention(c) (P, UInt32) -> P?).self),
            let h = sym(gst, "gst_mini_object_unref", (@convention(c) (P) -> Void).self),
            let i = sym(gst, "gst_object_unref", (@convention(c) (P) -> Void).self),
            let j = sym(gst, "gst_message_parse_error", (@convention(c) (P, UnsafeMutablePointer<P?>, P?) -> Void).self),
            let k = sym(gst, "gst_element_query_position", (@convention(c) (P, Int32, UnsafeMutablePointer<Int64>) -> Int32).self),
            let l = sym(gst, "gst_element_query_duration", (@convention(c) (P, Int32, UnsafeMutablePointer<Int64>) -> Int32).self),
            let m = sym(gst, "gst_element_seek_simple", (@convention(c) (P, Int32, UInt32, Int64) -> Int32).self),
            let n = sym(gst, "gst_sample_get_caps", (@convention(c) (P) -> P?).self),
            let o = sym(gst, "gst_sample_get_buffer", (@convention(c) (P) -> P?).self),
            let p = sym(gst, "gst_caps_get_structure", (@convention(c) (P, UInt32) -> P?).self),
            let q = sym(gst, "gst_structure_get_int", (@convention(c) (P, UnsafePointer<CChar>, UnsafeMutablePointer<Int32>) -> Int32).self),
            let r = sym(gst, "gst_buffer_map", (@convention(c) (P, P, UInt32) -> Int32).self),
            let s = sym(gst, "gst_buffer_unmap", (@convention(c) (P, P) -> Void).self),
            let t = sym(app, "gst_app_sink_try_pull_sample", (@convention(c) (P, UInt64) -> P?).self),
            let u = sym(gobj, "g_object_set_property", (@convention(c) (P, UnsafePointer<CChar>, P) -> Void).self),
            let v = sym(gobj, "g_value_init", (@convention(c) (P, UInt) -> P?).self),
            let w = sym(gobj, "g_value_set_string", (@convention(c) (P, UnsafePointer<CChar>) -> Void).self),
            let x = sym(gobj, "g_value_set_object", (@convention(c) (P, P?) -> Void).self),
            let y = sym(gobj, "g_value_set_double", (@convention(c) (P, Double) -> Void).self),
            let z = sym(gobj, "g_value_unset", (@convention(c) (P) -> Void).self)
        else { return nil }
        gstInit = a; factoryMake = b; parseBin = c; binByName = d; setState = e
        getBus = f; popFiltered = g; miniUnref = h; objectUnref = i; parseError = j
        queryPosition = k; queryDuration = l; seekSimple = m; sampleCaps = n
        sampleBuffer = o; capsStructure = p; structureInt = q; bufferMap = r
        bufferUnmap = s; appPull = t; setProperty = u; valueInit = v
        valueSetString = w; valueSetObject = x; valueSetDouble = y; valueUnset = z
        a(nil, nil)
    }
}

final class GStreamerPlayer: MediaPlayer {
    private let lib: GstLib
    private var playbin: UnsafeMutableRawPointer?
    private var appsink: UnsafeMutableRawPointer?
    private var bus: UnsafeMutableRawPointer?
    private var wantPlaying = false
    private var _volume = 1.0
    private(set) var status: MediaPlayerStatus = .idle

    // GstState / GstFormat / GstMessageType / GType values from the stable ABI.
    private let stateNull: Int32 = 1, statePaused: Int32 = 3, statePlaying: Int32 = 4
    private let formatTime: Int32 = 3
    private let msgEOS: UInt32 = 1, msgError: UInt32 = 2
    private let gTypeString: UInt = 16 << 2, gTypeObject: UInt = 20 << 2
    private let gTypeDouble: UInt = 15 << 2

    init?() {
        guard let lib = GstLib.shared else { return nil }
        self.lib = lib
    }

    deinit { stop() }

    // MARK: GValue helpers (a GValue is 24 bytes)

    private func withValue(_ type: UInt, _ set: (UnsafeMutableRawPointer) -> Void,
                           on object: UnsafeMutableRawPointer, _ property: String) {
        let v = UnsafeMutableRawPointer.allocate(byteCount: 24, alignment: 8)
        defer { v.deallocate() }
        v.initializeMemory(as: UInt8.self, repeating: 0, count: 24)
        _ = lib.valueInit(v, type)
        set(v)
        lib.setProperty(object, property, v)
        lib.valueUnset(v)
    }

    private func setString(_ o: UnsafeMutableRawPointer, _ p: String, _ s: String) {
        withValue(gTypeString, { self.lib.valueSetString($0, s) }, on: o, p)
    }

    // MARK: Control

    func open(url: String) {
        stop()
        guard let pb = lib.factoryMake("playbin", nil) else {
            status = .failed("GStreamer playbin unavailable"); return
        }
        var error: UnsafeMutableRawPointer? = nil
        let desc = "videoconvert ! videoscale ! appsink name=sink " +
            "caps=video/x-raw,format=RGBA max-buffers=4 drop=true sync=true"
        if let sinkBin = lib.parseBin(desc, 1, &error), let sink = lib.binByName(sinkBin, "sink") {
            withValue(gTypeObject, { self.lib.valueSetObject($0, sinkBin) }, on: pb, "video-sink")
            appsink = sink
        }
        setString(pb, "uri", url)
        playbin = pb
        bus = lib.getBus(pb)
        applyVolume()
        wantPlaying = true
        _ = lib.setState(pb, statePlaying)
        status = .loading
    }

    func play() {
        guard let pb = playbin else { return }
        if status == .ended { seek(to: 0) }
        wantPlaying = true
        _ = lib.setState(pb, statePlaying)
        if status == .paused { status = .playing }
    }

    func pause() {
        guard let pb = playbin else { return }
        wantPlaying = false
        _ = lib.setState(pb, statePaused)
        if status == .playing { status = .paused }
    }

    func stop() {
        if let pb = playbin {
            _ = lib.setState(pb, stateNull)
            lib.objectUnref(pb)
        }
        if let appsink { lib.objectUnref(appsink) }
        if let bus { lib.objectUnref(bus) }
        playbin = nil; appsink = nil; bus = nil
        status = .idle
    }

    func seek(to seconds: Double) {
        guard let pb = playbin else { return }
        let ns = Int64(max(0, seconds) * 1_000_000_000)
        _ = lib.seekSimple(pb, formatTime, 3 /* FLUSH | ACCURATE */, ns)
        if status == .ended { status = wantPlaying ? .playing : .paused }
    }

    var volume: Double {
        get { _volume }
        set { _volume = min(max(newValue, 0), 1); applyVolume() }
    }

    private func applyVolume() {
        guard let pb = playbin else { return }
        let v = _volume
        withValue(gTypeDouble, { self.lib.valueSetDouble($0, v) }, on: pb, "volume")
    }

    // MARK: Position

    var position: Double { query(lib.queryPosition) }
    var duration: Double { query(lib.queryDuration) }

    private func query(_ fn: @convention(c) (UnsafeMutableRawPointer, Int32, UnsafeMutablePointer<Int64>) -> Int32) -> Double {
        guard let pb = playbin else { return 0 }
        var ns: Int64 = 0
        guard fn(pb, formatTime, &ns) != 0 else { return 0 }
        return Double(ns) / 1_000_000_000
    }

    // MARK: Polling

    func pollFrame() -> MediaFrame? {
        drainBus()
        guard playbin != nil else { return nil }
        if status == .loading, duration > 0 || position > 0 { status = wantPlaying ? .playing : .paused }
        guard let sink = appsink, let sample = lib.appPull(sink, 0) else { return nil }
        defer { lib.miniUnref(sample) }
        if status == .loading { status = .playing }
        guard let caps = lib.sampleCaps(sample), let st = lib.capsStructure(caps, 0),
              let buffer = lib.sampleBuffer(sample) else { return nil }
        var w: Int32 = 0, h: Int32 = 0
        _ = lib.structureInt(st, "width", &w)
        _ = lib.structureInt(st, "height", &h)
        guard w > 0, h > 0 else { return nil }
        // GstMapInfo: memory(8) flags(4+4) data(8) size(8) maxsize(8) + reserved.
        let info = UnsafeMutableRawPointer.allocate(byteCount: 128, alignment: 8)
        defer { info.deallocate() }
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 128)
        guard lib.bufferMap(buffer, info, 1 /* READ */) != 0 else { return nil }
        defer { lib.bufferUnmap(buffer, info) }
        guard let data = info.load(fromByteOffset: 16, as: UnsafeRawPointer?.self) else { return nil }
        let size = info.load(fromByteOffset: 24, as: Int.self)
        let pixels = [UInt8](UnsafeRawBufferPointer(start: data, count: size))
        return MediaFrame(pixels: pixels, width: Int(w), height: Int(h))
    }

    private func drainBus() {
        guard let bus else { return }
        while let m = lib.popFiltered(bus, msgEOS) { lib.miniUnref(m); status = .ended }
        while let m = lib.popFiltered(bus, msgError) {
            var err: UnsafeMutableRawPointer? = nil
            lib.parseError(m, &err, nil)
            // GError: domain(4) code(4) message(char*) — message at offset 8.
            var text = "playback error"
            if let err, let c = err.load(fromByteOffset: 8, as: UnsafePointer<CChar>?.self) {
                text = String(cString: c)
            }
            status = .failed(text)
            lib.miniUnref(m)
        }
    }
}
#endif
