// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Images on the web: a PNG decoded by the browser and drawn by skwasm. The
// framework has no `Image` widget yet, so this goes the long way that
// widget will take — instantiateImageCodec, a frame, canvas.drawImage — and
// is the check that the page's decode path (docs/plans/wasm.md) works.
//
//   build/web-app.sh WebImages --serve

#if os(WASI)
import ExampleHost
import Flutter
import FlutterSwiftBridge

final class ImagePainter: CustomPainter {
    var image: Image?

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let paint = Paint()
        paint.color = Color(0xFF1C_2430)
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint)
        guard let image else { return }
        // Scaled up 3x, nearest-neighbour would show the pixels; linear is
        // the default and shows the decode.
        let w = Double(image.width) * 3, h = Double(image.height) * 3
        canvas.drawImageRect(
            image, Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)),
            Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h), Paint())
    }
}

final class ImagePage: StatefulWidget {
    override func createState() -> State<StatefulWidget> { ImagePageState() }
}

final class ImagePageState: State<StatefulWidget> {
    private let painter = ImagePainter()
    private var status = "decoding…"

    override func initState() {
        super.initState()
        Task {
            do {
                let codec = try await instantiateImageCodec(quadrantsPNG)
                let frame = try await codec.getNextFrame()
                painter.image = frame.image
                setState { status = "\(frame.image.width)×\(frame.image.height), decoded by the browser" }
                print("[WebImages] decoded \(frame.image.width)x\(frame.image.height)")
            } catch {
                setState { status = "failed: \(error)" }
                print("[WebImages] failed: \(error)")
            }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        Column(children: [
            Expanded(child: CustomPaint(painter: painter, child: SizedBox(width: Double.infinity, height: Double.infinity))),
            Padding(
                padding: EdgeInsets(all: 12),
                child: Text(status, style: TextStyle(color: Color(0xFFB0_BEC5), fontSize: 14))),
        ])
    }
}

runExampleApp(title: "Web Images") { Directionality(textDirection: .ltr, child: ImagePage()) }
#endif
