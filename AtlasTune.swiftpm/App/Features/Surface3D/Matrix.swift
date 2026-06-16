import Foundation
import simd

/// Minimal 4x4 matrix helpers for the surface camera. Kept local to the rendering feature so the
/// engine stays graphics-free.
enum Matrix {
    static func translation(_ t: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    static func perspective(fovYRadians: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let y = 1 / tan(fovYRadians * 0.5)
        let x = y / aspect
        let z = far / (near - far)
        return float4x4(columns: (
            SIMD4(x, 0, 0, 0),
            SIMD4(0, y, 0, 0),
            SIMD4(0, 0, z, -1),
            SIMD4(0, 0, z * near, 0)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)
        return float4x4(columns: (
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-dot(s, eye), -dot(u, eye), dot(f, eye), 1)
        ))
    }
}
