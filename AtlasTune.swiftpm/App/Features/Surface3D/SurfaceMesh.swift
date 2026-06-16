import Foundation
import simd
import AtlasTuneCore

/// CPU-side vertex matching `SurfaceVertex` in Surface.metal.
struct SurfaceVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var height: Float
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
