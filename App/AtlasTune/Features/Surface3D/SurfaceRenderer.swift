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
    private var depthState: MTLDepthStencilState?

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount: Int = 0
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
    }

    // MARK: Setup

    private func buildPipeline(view: MTKView) {
        // Prefer the precompiled default library (Xcode builds Surface.metal). When that is
        // unavailable — e.g. inside Swift Playgrounds, which does not compile .metal files — fall
        // back to compiling the shader from source at runtime.
        let library: MTLLibrary
        if let defaultLibrary = device.makeDefaultLibrary(),
           defaultLibrary.makeFunction(name: "surface_vertex") != nil {
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
        guard !mesh.vertices.isEmpty else { return }
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
        guard let pipelineState,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let vertexBuffer, let indexBuffer, indexCount > 0 else {
            return
        }

        var uniforms = makeUniforms()
        encoder.setRenderPipelineState(pipelineState)
        if let depthState { encoder.setDepthStencilState(depthState) }
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawIndexedPrimitives(
            type: .triangle, indexCount: indexCount, indexType: .uint32,
            indexBuffer: indexBuffer, indexBufferOffset: 0
        )
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
