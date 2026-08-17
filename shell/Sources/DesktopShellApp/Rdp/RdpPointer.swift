// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)
import Foundation
import FlutterEmbedderBridge

/// Pointer state for display mode, where there is no libinput and no seat —
/// the RDP client is the only input device the desktop has.
///
/// This is `FlDrmInput::InjectPointerAbs` ported out of the engine: the DRM
/// version had to fold into an existing virtual-desktop pointer shared with
/// real devices, but here the client owns the pointer outright, so the
/// transform collapses to "the client's pixels are the desktop's pixels".
/// The part worth keeping is the phase derivation — RDP reports absolute
/// button state, Flutter wants transitions, and getting that wrong produces
/// clicks that never release.
///
/// Main queue only: the peer thread hops here before calling.
final class RdpPointer {

    private var engine: OpaquePointer?
    private var added = false
    private var down = false
    private var buttons: Int64 = 0

    func attach(engine: OpaquePointer?) {
        self.engine = engine
    }

    /// One report from the client: position in desktop physical pixels,
    /// |buttons| the absolute Flutter mask (1 primary, 2 secondary, 4
    /// middle), wheel deltas already in Flutter's pixel units.
    func handle(x: Double, y: Double, buttons newButtons: Int64,
                wheelDX: Double, wheelDY: Double) {
        guard let engine else { return }

        if !added {
            send(engine, phase: kAdd, x: x, y: y, buttons: 0)
            added = true
        }

        // Press before release, so a report that swaps buttons in one packet
        // still reads as a continuous gesture rather than an up/down pair.
        let pressed = newButtons & ~buttons
        let released = buttons & ~newButtons
        buttons = newButtons

        if pressed != 0 {
            down = true
            send(engine, phase: kDown, x: x, y: y, buttons: buttons)
        } else if released != 0 {
            down = (buttons != 0)
            send(engine, phase: down ? kMove : kUp, x: x, y: y,
                 buttons: buttons)
        } else {
            send(engine, phase: down ? kMove : kHover, x: x, y: y,
                 buttons: buttons)
        }

        // Scroll rides its own event, as the libinput path does — a single
        // event carrying both a phase change and a scroll signal is not a
        // shape the framework expects.
        if wheelDX != 0 || wheelDY != 0 {
            send(engine, phase: down ? kMove : kHover, x: x, y: y,
                 buttons: buttons, scrollX: wheelDX, scrollY: wheelDY)
        }
    }

    /// The client went away: release anything held, then withdraw the
    /// pointer. Without this a disconnect mid-drag leaves the desktop
    /// convinced a button is still down.
    func reset() {
        guard let engine, added else { return }
        if down {
            send(engine, phase: kUp, x: lastX, y: lastY, buttons: 0)
            down = false
        }
        buttons = 0
        send(engine, phase: kRemove, x: lastX, y: lastY, buttons: 0)
        added = false
    }

    private var lastX: Double = 0
    private var lastY: Double = 0

    private func send(_ engine: OpaquePointer, phase: FlutterPointerPhase,
                      x: Double, y: Double, buttons: Int64,
                      scrollX: Double = 0, scrollY: Double = 0) {
        lastX = x
        lastY = y
        var event = FlutterPointerEvent()
        event.struct_size = MemoryLayout<FlutterPointerEvent>.size
        event.phase = phase
        event.timestamp = Int(FlutterEngineGetCurrentTime() / 1000)  // ns → µs
        event.x = x
        event.y = y
        event.device = 0
        event.device_kind = kFlutterPointerDeviceKindMouse
        event.buttons = buttons
        event.view_id = 0
        if scrollX != 0 || scrollY != 0 {
            event.signal_kind = kFlutterPointerSignalKindScroll
            event.scroll_delta_x = scrollX
            event.scroll_delta_y = scrollY
        }
        FlutterEngineSendPointerEvent(engine, &event, 1)
    }
}
#endif
