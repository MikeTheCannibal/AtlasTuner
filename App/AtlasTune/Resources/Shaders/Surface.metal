#include <metal_stdlib>
using namespace metal;

// Shared layout with SurfaceRenderer.swift.
struct SurfaceVertex {
    float3 position;
    float3 normal;
    float   height; // normalised 0..1 for colour mapping
};

struct Uniforms {
    float4x4 modelViewProjection;
    float4x4 normalMatrix;
    float3   lightDirection;
    float    highlight; // >0 tints modified cells
};

struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float  height;
};

vertex VertexOut surface_vertex(const device SurfaceVertex *vertices [[buffer(0)]],
                                constant Uniforms &uniforms [[buffer(1)]],
                                uint vid [[vertex_id]]) {
    SurfaceVertex v = vertices[vid];
    VertexOut out;
    out.position = uniforms.modelViewProjection * float4(v.position, 1.0);
    out.normal = (uniforms.normalMatrix * float4(v.normal, 0.0)).xyz;
    out.height = v.height;
    return out;
}

// Blue (low) -> green -> red (high) height ramp.
static float3 heightColor(float t) {
    float3 low  = float3(0.10, 0.35, 0.85);
    float3 mid  = float3(0.15, 0.80, 0.35);
    float3 high = float3(0.90, 0.20, 0.15);
    if (t < 0.5) {
        return mix(low, mid, t * 2.0);
    }
    return mix(mid, high, (t - 0.5) * 2.0);
}

fragment float4 surface_fragment(VertexOut in [[stage_in]],
                                 constant Uniforms &uniforms [[buffer(1)]]) {
    float3 n = normalize(in.normal);
    float diffuse = max(dot(n, normalize(uniforms.lightDirection)), 0.0);
    float ambient = 0.35;
    float3 base = heightColor(clamp(in.height, 0.0, 1.0));
    float3 lit = base * (ambient + diffuse * 0.75);
    return float4(lit, 1.0);
}

struct LineVertex {
    float3 position;
    float3 color;
};

struct LineOut {
    float4 position [[position]];
    float3 color;
};

vertex LineOut line_vertex(const device LineVertex *vertices [[buffer(0)]],
                           constant Uniforms &uniforms [[buffer(1)]],
                           uint vid [[vertex_id]]) {
    LineVertex v = vertices[vid];
    LineOut out;
    out.position = uniforms.modelViewProjection * float4(v.position, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 line_fragment(LineOut in [[stage_in]]) {
    return float4(in.color, 1.0);
}
