// VerticesBridge, over skwasm's vertices.cpp.
import CSkwasm

extension flutter.swift_bridge {
    public final class VerticesBridge {
        /// skwasm's wrapper around the DlVertices, which is what
        /// canvas_drawVertices takes. 0 if the arguments were unusable, and
        /// again after Dispose.
        public private(set) var skHandle: sk_ptr = 0

        private var disposed = false

        /// `positions` and `texture_coordinates` are x,y pairs and their
        /// counts are in FLOATS, not points. `colors` are ARGB words.
        public init(
            _ mode: Int32,
            _ positions: UnsafePointer<Float>?, _ position_count: Int32,
            _ texture_coordinates: UnsafePointer<Float>?, _ texture_coordinate_count: Int32,
            _ colors: UnsafePointer<Int32>?, _ color_count: Int32,
            _ indices: UnsafePointer<UInt16>?, _ index_count: Int32
        ) {
            guard positions != nil, position_count > 0 else { return }
            let vertexCount = Int(position_count) / 2
            guard vertexCount > 0 else { return }

            // skwasm has one count for all three per-vertex arrays, so each
            // is padded out to it: nothing upstream promises they match.
            let hasTextureCoordinates = texture_coordinates != nil && texture_coordinate_count > 0
            let hasColors = colors != nil && color_count > 0
            let hasIndices = indices != nil && index_count > 0

            let rawPositions = SkHeapArray(
                positions, count: vertexCount * 2, capacity: vertexCount * 2)
            let rawTextureCoordinates = SkHeapArray(
                hasTextureCoordinates ? texture_coordinates : nil,
                count: Int(texture_coordinate_count), capacity: vertexCount * 2)
            let rawColors = SkHeapArray(
                hasColors ? colors : nil, count: Int(color_count), capacity: vertexCount)
            let rawIndices = SkHeapArray(
                hasIndices ? indices : nil, count: Int(index_count))
            defer {
                rawPositions.dispose()
                rawTextureCoordinates.dispose()
                rawColors.dispose()
                rawIndices.dispose()
            }

            // VertexMode, DlVertexMode and skwasm agree: 0 triangles,
            // 1 triangle strip, 2 triangle fan.
            skHandle = vertices_create(
                mode, Int32(vertexCount), rawPositions.pointer,
                rawTextureCoordinates.pointer, rawColors.pointer,
                hasIndices ? index_count : 0, rawIndices.pointer)
        }

        deinit { release() }

        private func release() {
            if skHandle != 0 { vertices_dispose(skHandle) }
            skHandle = 0
        }

        public func IsValid() -> Bool { skHandle != 0 }

        public func Dispose() {
            release()
            disposed = true
        }

        public func IsDisposed() -> Bool { disposed }
    }
}
