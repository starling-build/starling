// A CGEvent clicker, for driving the terminal's panes on macOS.
//
//   swiftc -O -o click click.swift
//   click <x> <y> [count]        screen points, origin top-left
//
// System Events' own `click at` does NOT reach a Flutter view: it returns a
// plausible target ("group 1 of window Starling Terminal") and nothing
// happens. Keystrokes go through fine; only clicks are swallowed. Since a
// pane is focused by CLICK and nothing else — there is no keyboard binding
// for "next pane" — a demo that puts different work in different panes needs
// this, and so does any UI test that touches more than the newest pane.
//
// The first click on an INACTIVE macOS window is eaten by activation, so pass
// a count of 2 when the app may not be frontmost.
import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else {
    FileHandle.standardError.write(Data("usage: click <x> <y> [count]\n".utf8))
    exit(2)
}
let count = a.count > 3 ? Int(a[3]) ?? 1 : 1
let pt = CGPoint(x: x, y: y)

func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
}

// Move first: a down/up at a position the cursor has never been at is
// delivered, but the view never sees the hover that precedes a real click.
post(.mouseMoved)
usleep(80_000)
for _ in 0..<count {
    post(.leftMouseDown)
    usleep(40_000)
    post(.leftMouseUp)
    usleep(120_000)
}
