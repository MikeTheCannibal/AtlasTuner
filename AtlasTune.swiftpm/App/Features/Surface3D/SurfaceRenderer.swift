import Foundation
import Metal
import MetalKit
import simd
import AtlasTuneCore

/// Matches `Uniforms` in Surface.metal.
private struct Uniforms {
    var modelViewProjection: float4x4
    var normalMatrix: float4x4
    var lightDirection: SIMD3<Float>
    var highlight: Float
}

/// Renders a calibration surface with Metal at the device's max refresh rate (120 Hz on iPad
/// Pro). The renderer is intentionally thin: mesh generation lives in `SurfaceMesh`, camera
/// state is owned by the view layer and pushed in via `camera`.
final class SurfaceRenderer: NSObject, MTKViewDelegate {
    /// Orbit camera state driven by gestures (rotation in radians, zoom as distance).
    struct Camera {
        var yaw: Float = .pi / 4
        var pitch: Float = .pi / 6
        var distance: Float = 2.4
        var pan: SIMD2<Float> = .zero
    }

    var camera = Camera()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var linePipelineState: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0
    private var lineBuffer: MTLBuffer?
    private var lineVertexCount: Int = 0
    private var aspect: Float = 1

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        super.init()

        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.preferredFramesPerSecond = 120
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)

        buildPipeline(view: mtkView)
        buildDepthState()
        buildAxisLines()
    }

    // MARK: Setup

    private func buildPipeline(view: MTKView) {
        // Prefer the precompiled default library (Xcode builds Surface.metal). When that is
        // unavailable — e.g. inside Swift Playgrounds, which does not compile .metal files — fall
        // back to compiling the shader from source at runtime.
        // Require the full function set so a stale precompiled library (without the newer line
        // shaders) falls back to runtime compilation instead of silently dropping the axes.
        let library: MTLLibrary
        if let defaultLibrary = device.makeDefaultLibrary(),
           defaultLibrary.makeFunction(name: "surface_vertex") != nil,
           defaultLibrary.makeFunction(name: "line_vertex") != nil {
            library = defaultLibrary
        } else if let runtimeLibrary = try? device.makeLibrary(source: SurfaceShaderSource.metal, options: nil) {
            library = runtimeLibrary
        } else {
            return
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "surface_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "surface_fragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)

        let lineDescriptor = MTLRenderPipelineDescriptor()
        lineDescriptor.vertexFunction = library.makeFunction(name: "line_vertex")
        lineDescriptor.fragmentFunction = library.makeFunction(name: "line_fragment")
        lineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        lineDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        linePipelineState = try? device.makeRenderPipelineState(descriptor: lineDescriptor)
    }

    /// The axis frame is static geometry in normalised surface space — build it once.
    private func buildAxisLines() {
        let lines = SurfaceMesh.axisLines()
        guard !lines.isEmpty else { return }
        lineBuffer = device.makeBuffer(
            bytes: lines,
            length: MemoryLayout<LineVertex>.stride * lines.count,
            options: .storageModeShared
        )
        lineVertexCount = lines.count
    }

    private func buildDepthState() {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: descriptor)
    }

    // MARK: Mesh

    func update(table: CalibrationTable) {
        let mesh = SurfaceMesh.build(from: table)
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty else {
            // No drawable triangles (scalar / single-row tables): clear the surface but keep
            // rendering the axis frame. makeBuffer(length: 0) is invalid, so never call it.
            vertexBuffer = nil
            indexBuffer = nil
            indexCount = 0
            return
        }
        vertexBuffer = device.makeBuffer(
            bytes: mesh.vertices,
            length: MemoryLayout<SurfaceVertex>.stride * mesh.vertices.count,
            options: .storageModeShared
        )
        indexBuffer = device.makeBuffer(
            bytes: mesh.indices,
            length: MemoryLayout<UInt32>.stride * mesh.indices.count,
            options: .storageModeShared
        )
        indexCount = mesh.indices.count
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        aspect = size.height > 0 ? Float(size.width / size.height) : 1
    }

    func draw(in view: MTKView) {
        // The encoder is created only after all failable checks, and every path below ends it —
        // returning between makeRenderCommandEncoder and endEncoding aborts with a Metal
        // assertion ("Command encoder released without endEncoding"), which is exactly what
        // happened when a mesh had no triangles (1-row/scalar tables).
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        var uniforms = makeUniforms()
        if let depthState { encoder.setDepthStencilState(depthState) }

        if let pipelineState, let vertexBuffer, let indexBuffer, indexCount > 0 {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: indexCount, indexType: .uint32,
                indexBuffer: indexBuffer, indexBufferOffset: 0
            )
        }

        // Axis frame: drawn even when the surface mesh is empty so orientation is always visible.
        if let linePipelineState, let lineBuffer, lineVertexCount > 0 {
            encoder.setRenderPipelineState(linePipelineState)
            encoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: lineVertexCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: Camera math

    private func makeUniforms() -> Uniforms {
        let model = Matrix.translation(SIMD3(camera.pan.x, camera.pan.y, 0))
        let eye = SIMD3<Float>(
            camera.distance * cos(camera.pitch) * sin(camera.yaw),
            camera.distance * sin(camera.pitch),
            camera.distance * cos(camera.pitch) * cos(camera.yaw)
        )
        let view = Matrix.lookAt(eye: eye, center: .zero, up: SIMD3(0, 1, 0))
        let projection = Matrix.perspective(fovYRadians: .pi / 3, aspect: aspect, near: 0.01, far: 100)
        let mvp = projection * view * model
        return Uniforms(
            modelViewProjection: mvp,
            normalMatrix: model.inverse.transpose,
            lightDirection: normalize(SIMD3(0.4, 0.9, 0.6)),
            highlight: 0
        )
    }
}
