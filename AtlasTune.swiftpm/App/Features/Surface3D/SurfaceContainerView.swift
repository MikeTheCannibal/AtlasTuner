import SwiftUI
import MetalKit
import AtlasTuneCore

/// SwiftUI wrapper around an `MTKView` driving `SurfaceRenderer`. Pinch zooms, one-finger drag
/// orbits, two-finger drag pans — the gesture set called for in the spec. Rendering targets
/// 120 FPS on the iPad Pro.
struct SurfaceContainerView: View {
    let table: CalibrationTable

    @State private var yaw: Float = .pi / 4
    @State private var pitch: Float = .pi / 6
    @State private var distance: Float = 2.4
    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1

    var body: some View {
        MetalSurfaceView(table: table, yaw: yaw, pitch: pitch, distance: distance)
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        yaw += Float(value.translation.width) * 0.005
                        pitch = max(-1.4, min(1.4, pitch + Float(value.translation.height) * 0.005))
                    }
            )
            .gesture(
                MagnifyGesture()
                    .updating($pinchScale) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        distance = max(0.8, min(8, distance / Float(value.magnification)))
                    }
            )
            .overlay(alignment: .bottomLeading) { legend }
            .ignoresSafeArea(edges: .bottom)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(table.definition.name).font(.headline)
            Text("Min \(table.minValue, format: .number) · Max \(table.maxValue, format: .number) \(table.definition.unit)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }
}

/// `UIViewRepresentable` bridging to MetalKit.
struct MetalSurfaceView: UIViewRepresentable {
    let table: CalibrationTable
    let yaw: Float
    let pitch: Float
    let distance: Float

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let renderer = SurfaceRenderer(mtkView: view) else { return view }
        renderer.update(table: table)
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if context.coordinator.tableID != table.definition.id {
            renderer.update(table: table)
            context.coordinator.tableID = table.definition.id
        }
        renderer.camera.yaw = yaw
        renderer.camera.pitch = pitch
        renderer.camera.distance = distance
    }

    final class Coordinator {
        var renderer: SurfaceRenderer?
        var tableID: String?
    }
}
