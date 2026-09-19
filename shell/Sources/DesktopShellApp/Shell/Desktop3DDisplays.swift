// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// The embedder can reuse an idle layer tree after a texture notification.
/// Expose a paint-only invalidation for ambient frames on each output;
/// rebuilding the whole shell at the animation rate is unnecessary.
private final class CitySceneTexture: LeafRenderObjectWidget {
    let textureId: Int
    let register: (TextureBox) -> Void
    init(textureId: Int, register: @escaping (TextureBox) -> Void) {
        self.textureId = textureId
        self.register = register
        super.init()
    }
    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let box = TextureBox(textureId: textureId, filterQuality: .low)
        register(box)
        return box
    }
    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        guard let box = renderObject as? TextureBox else { return }
        box.textureId = textureId
        register(box)
    }
}

extension _DesktopShellState {
    /// All monitors are crops of ONE render, with a single optical centre
    /// on the primary display. Logical coordinates keep mixed-DPI seams
    /// continuous; no camera or world is duplicated for another output.
    var _desktop3DCanvas: Rect {
        displayLayout?.virtualBounds ?? Rect.fromLTWH(0, 0, screenWidth, screenHeight)
    }

    func _desktop3DViewport(on output: Rect) -> Widget {
        let canvas = _desktop3DCanvas
        return ClipRect(child: Stack(fit: .expand, children: [
            Positioned(left: canvas.left - output.left, top: canvas.top - output.top,
                       width: canvas.width, height: canvas.height,
                       child: CitySceneTexture(textureId: Int(environmentTextureId)) { [weak self] box in
                           self?._sceneRepaints["\(output.left),\(output.top)"] = { [weak box] in
                               box?.markNeedsPaint()
                           }
                       }),
        ]))
    }

    func _desktop3DOutputId(for win: WindowInfo) -> Int {
        displayLayout?.owningOutput(ofRect: win.rect).id ?? 0
    }
}
