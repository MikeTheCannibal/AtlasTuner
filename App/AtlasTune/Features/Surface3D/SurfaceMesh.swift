import Foundation
import simd
import AtlasTuneCore

/// CPU-side vertex matching `SurfaceVertex` in Surface.metal.
struct SurfaceVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var height: Float
}

/// CPU-side vertex matching `LineVertex` in Surface.metal (axis/reference lines).
struct LineVertex {
    var position: SIMD3<Float>
    var color: SIMD3<Float>
}

/// Builds a triangulated mesh from a calibration table. Axes map to X/Z on a unit footprint and
/// the (normalised) value maps to Y, so any table renders to a comparable surface regardless of
/// its real units. Smooth per-vertex normals give the lit look the spec asks for.
enum SurfaceMesh {
    /// Returns interleaved vertices and triangle indices for `table`.
    static func build(from table: CalibrationTable, heightScale: Float = 0.5) -> (vertices: [SurfaceVertex], indices: [UInt32]) {
        let rows = max(table.rows, 1)
        let cols = max(table.columns, 1)
        let minV = table.minValue
        let maxV = table.maxValue
        let span = maxV - minV
        func norm(_ v: Double) -> Float { span > 0 ? Float((v - minV) / span) : 0 }

        // Positions on a centered unit grid.
        var grid = [[SIMD3<Float>]](repeating: [SIMD3<Float>](repeating: .zero, count: cols), count: rows)
        for r in 0..<rows {
            for c in 0..<cols {
                let x = cols > 1 ? Float(c) / Float(cols - 1) - 0.5 : 0
                let z = rows > 1 ? Float(r) / Float(rows - 1) - 0.5 : 0
                let y = norm(table.values[r][c]) * heightScale
                grid[r][c] = SIMD3(x, y, z)
            }
        }

        var vertices: [SurfaceVertex] = []
        vertices.reserveCapacity(rows * cols)
        for r in 0..<rows {
            for c in 0..<cols {
                vertices.append(SurfaceVertex(
                    position: grid[r][c],
                    normal: vertexNormal(grid, r, c, rows, cols),
                    height: norm(table.values[r][c])
                ))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity((rows - 1) * (cols - 1) * 6)
        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let i0 = UInt32(r * cols + c)
                let i1 = UInt32(r * cols + c + 1)
                let i2 = UInt32((r + 1) * cols + c)
                let i3 = UInt32((r + 1) * cols + c + 1)
                indices.append(contentsOf: [i0, i2, i1, i1, i2, i3])
            }
        }
        return (vertices, indices)
    }

    // MARK: Axis reference lines

    /// Conventional axis colours: X (columns) red, Y (value) green, Z (rows) blue.
    static let xAxisColor = SIMD3<Float>(0.95, 0.30, 0.25)
    static let yAxisColor = SIMD3<Float>(0.30, 0.85, 0.40)
    static let zAxisColor = SIMD3<Float>(0.35, 0.55, 0.95)

    /// Line-segment vertices (pairs) for the axis frame drawn under/behind every surface: three
    /// coloured axes anchored at the front-left corner, the remaining floor border in grey, and
    /// quarter tick marks so rotation always has a fixed reference to read against.
    static func axisLines(heightScale: Float = 0.5) -> [LineVertex] {
        let grey = SIMD3<Float>(0.45, 0.45, 0.50)
        var vertices: [LineVertex] = []
        func line(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ color: SIMD3<Float>) {
            vertices.append(LineVertex(position: a, color: color))
            vertices.append(LineVertex(position: b, color: color))
        }

        let origin = SIMD3<Float>(-0.5, 0, 0.5)                    // front-left corner
        line(origin, SIMD3(0.5, 0, 0.5), xAxisColor)               // X → columns (front edge)
        line(origin, SIMD3(-0.5, 0, -0.5), zAxisColor)             // Z → rows (left edge)
        line(origin, SIMD3(-0.5, heightScale, 0.5), yAxisColor)    // Y ↑ value

        line(SIMD3(0.5, 0, 0.5), SIMD3(0.5, 0, -0.5), grey)        // rest of the floor border
        line(SIMD3(0.5, 0, -0.5), SIMD3(-0.5, 0, -0.5), grey)

        // Quarter ticks along each coloured axis.
        let tick: Float = 0.02
        for t in [Float(0.25), 0.5, 0.75] {
            line(SIMD3(-0.5 + t, 0, 0.5), SIMD3(-0.5 + t, tick, 0.5), xAxisColor)
            line(SIMD3(-0.5, 0, 0.5 - t), SIMD3(-0.5, tick, 0.5 - t), zAxisColor)
            line(SIMD3(-0.5, heightScale * t, 0.5), SIMD3(-0.5 + tick, heightScale * t, 0.5), yAxisColor)
        }
        return vertices
    }

    private static func vertexNormal(_ grid: [[SIMD3<Float>]], _ r: Int, _ c: Int, _ rows: Int, _ cols: Int) -> SIMD3<Float> {
        let left = grid[r][max(c - 1, 0)]
        let right = grid[r][min(c + 1, cols - 1)]
        let down = grid[max(r - 1, 0)][c]
        let up = grid[min(r + 1, rows - 1)][c]
        let normal = simd_cross(up - down, right - left)
        let length = simd_length(normal)
        return length > 0 ? normal / length : SIMD3(0, 1, 0)
    }
}
