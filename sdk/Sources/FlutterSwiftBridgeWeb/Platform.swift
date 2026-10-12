// The engine-facing half of PlatformDispatcher and ChannelBuffers. Natively
// these reach the shell through callbacks the engine registers at startup;
// here there is no engine, only the page, and whoever hosts the app
// (FlutterWeb) stands in for it by filling in `WebPlatform`.

// SwiftRuntimeCallbacks (swift_runtime_callbacks.h) lives in CSkwasm on the
// web, where elsewhere it comes with the clang module this one replaces.
// Re-exported so that SwiftRuntime finds it through FlutterSwiftBridge as it
// does on every other platform.
@_exported import CSkwasm

/// What the host provides. Set before the first frame; read on the one
/// thread a tab has.
public enum WebPlatform {
    /// Asks the page for one animation frame. The default does nothing, as
    /// the native bridge does before the engine has registered its callback.
    nonisolated(unsafe) public static var scheduleFrame: () -> Void = {}

    /// The route the app opens on — the host would take it from the URL.
    nonisolated(unsafe) public static var defaultRouteName: String = "/"

    /// 0 means "not set", which PlatformDispatcher.engineId reports as nil.
    nonisolated(unsafe) public static var engineId: Int64 = 0
}

extension flutter.swift_bridge {

    // MARK: - PlatformDispatcherBridge

    public final class PlatformDispatcherBridge {
        /// Backs GetDefaultRouteName, which returns a pointer into storage
        /// the bridge owns. Replaced on each call, so a pointer is good until
        /// the next one.
        private var routeName: UnsafeMutablePointer<CChar>?

        public init() {}

        deinit { routeName?.deallocate() }

        /// `int` in C++, so Int32. An id that does not fit is truncated
        /// rather than trapping: it is an opaque token, and the caller
        /// widens it to Int, which is 32 bits here anyway.
        public func GetEngineId() -> Int32 {
            Int32(truncatingIfNeeded: WebPlatform.engineId)
        }

        public func ScheduleFrame() {
            WebPlatform.scheduleFrame()
        }

        public func GetDefaultRouteName() -> UnsafePointer<CChar>? {
            routeName?.deallocate()
            let copy = WebPlatform.defaultRouteName.withCString { copyCString($0) }
            routeName = copy
            return UnsafePointer(copy)
        }
    }

    // MARK: - ChannelBuffersBridge

    public typealias SendChannelUpdateCallback =
        @convention(c) (UnsafePointer<CChar>?, Bool) -> Void

    public enum ChannelBuffersBridge {
        nonisolated(unsafe) private static var sendChannelUpdateCallback:
            SendChannelUpdateCallback?

        public static func SetSendChannelUpdateCallback(_ callback: SendChannelUpdateCallback?) {
            sendChannelUpdateCallback = callback
        }

        // WEB-TODO: nothing on the page listens for this. Natively it lets
        // the embedder know a channel has gained or lost its listener; the
        // web host would need it only once it routes platform messages from
        // JavaScript. Forwarded to the callback if someone registers one.
        public static func SendChannelUpdate(_ name: UnsafePointer<CChar>?, _ listening: Bool) {
            sendChannelUpdateCallback?(name, listening)
        }
    }
}

// MARK: - What the engine's library does for a host, and the page does not

extension flutter.swift_bridge {
    /// ICU data for the bridge's own text stack. There is none to load: the
    /// browser does the segmenting (starling_host_segment).
    public static func InitializeICU(_ path: String) -> Bool { true }

    /// PDF through skwasm's own Skia PDF backend (pdf_write — a Starling
    /// addition to lib/web_ui/skwasm, so it needs the skwasm built from our
    /// engine, not Google's published one; build/web-app.sh says which it
    /// staged). A tab has no file to write: the document is handed to the
    /// browser as a download named by `path`'s last component.
    // WEB-TODO: a picture is a texture here, which skwasm copies back for
    // the PDF — except one inside a shader (a tiled fill), which is left out.
    public static func WritePdf(
        _ path: String, _ displayLists: UnsafePointer<UnsafeRawPointer?>?,
        _ count: Int32, _ widths: UnsafePointer<Double>?, _ heights: UnsafePointer<Double>?,
        _ title: String?, _ author: String?
    ) -> Bool {
        guard let displayLists, let widths, let heights, count > 0 else { return false }
        let n = Int(count)
        let handles = (0 ..< n).map { skHandle(from: displayLists[$0]) }
        var sizes: [Float] = []
        for i in 0 ..< n {
            sizes.append(Float(widths[i]))
            sizes.append(Float(heights[i]))
        }
        let skTitle = title.map(makeSkString) ?? 0
        let skAuthor = author.map(makeSkString) ?? 0
        defer {
            if skTitle != 0 { skString_free(skTitle) }
            if skAuthor != 0 { skString_free(skAuthor) }
        }
        let data = withSkStack { stack in
            pdf_write(WebSurface.handle, stack.pointers(handles), count, stack.floats(sizes), skTitle, skAuthor)
        }
        guard data != 0 else { return false }
        defer { skData_dispose(data) }
        let bytes: [UInt8] = skRead(skData_getConstPointer(data), count: Int(skData_getSize(data)))
        guard !bytes.isEmpty else { return false }
        var name = String(path.split(separator: "/").last ?? "document.pdf")
        name.withUTF8 { nameBytes in
            bytes.withUnsafeBufferPointer { b in
                starling_host_download(nameBytes.baseAddress, UInt32(nameBytes.count),
                                       b.baseAddress, UInt32(b.count))
            }
        }
        return true
    }
}
