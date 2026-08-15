// Renders the Terminal app icon at 1024x1024 and writes a PNG.
// Run: swift build/macos/gen-icon.swift /tmp/icon-1024.png
// One-time generator for build/macos/Terminal.icns (see macos-app.sh); the
// .icns is checked in so the packaging path needs no AppKit at build time.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S: CGFloat = 1024

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()

// Apple's icon grid: the squircle occupies ~824pt of the 1024 canvas.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

// Dark terminal glass: near-black with a slight top-down lift.
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1),
])!
gradient.draw(in: path, angle: -90)

// Hairline highlight on the top edge, the way macOS window chrome catches light.
path.addClip()
let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 3, dy: 3), xRadius: 182, yRadius: 182)
edge.lineWidth = 6
NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
edge.stroke()

// The prompt: "❯" in the terminal's own Roboto Mono, plus a block cursor.
let fontURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("sdk/Sources/Flutter/Terminal/Fonts/RobotoMono-Bold.ttf")
var font = NSFont.monospacedSystemFont(ofSize: 320, weight: .bold)
if let data = try? Data(contentsOf: fontURL),
   let provider = CGDataProvider(data: data as CFData),
   let cgFont = CGFont(provider),
   let name = cgFont.postScriptName as String? {
    CTFontManagerRegisterGraphicsFont(cgFont, nil)
    font = NSFont(name: name, size: 320) ?? font
}
let prompt = NSAttributedString(string: "\u{276F}", attributes: [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 1),
])
let ps = prompt.size()
prompt.draw(at: NSPoint(x: rect.minX + 130, y: rect.midY - ps.height / 2 + 20))

let cursor = NSRect(x: rect.minX + 130 + ps.width + 60,
                    y: rect.midY - 10, width: 150, height: 46)
NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
cursor.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
