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
    var _desktop3DViewId: Int {
        _desktop3DViewOverride ?? _pointerOutputId ?? displayLayout?.host.id ?? 0
    }

    var _desktop3DHost: Rect {
        displayLayout?.outputs.first(where: { $0.id == _desktop3DViewId })?.logicalRect
            ?? Rect.fromLTWH(0, 0, screenWidth, screenHeight)
    }

    @discardableResult
    func _withDesktop3DOutput<T>(_ id: Int, _ body: () -> T) -> T {
        let previous = _desktop3DViewOverride
        _desktop3DViewOverride = id
        defer { _desktop3DViewOverride = previous }
        return body()
    }

    func _forEachDesktop3DOutput(_ body: () -> Void) {
        for id in displayLayout?.outputs.map({ $0.id }) ?? [0] {
            _withDesktop3DOutput(id, body)
        }
    }

    var _desktop3DCanvas: Rect { _desktop3DHost }

    func _desktop3DViewport(on output: Rect) -> Widget {
        let id = displayLayout?.owningOutput(ofRect: output).id ?? 0
        return _withDesktop3DOutput(id) {
            CitySceneTexture(textureId: Int(environmentTextureId)) { [weak self] box in
                self?._sceneRepaints["\(id)"] = { [weak box] in box?.markNeedsPaint() }
            }
        }
    }

    func _desktop3DOutputId(for win: WindowInfo) -> Int {
        displayLayout?.owningOutput(ofRect: win.rect).id ?? 0
    }
}
