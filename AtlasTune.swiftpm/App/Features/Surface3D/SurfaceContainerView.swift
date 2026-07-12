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

    // The camera the renderer sees = committed state + the in-flight gesture, so orbit/zoom track
    // the pointer in real time; `.onEnded` then folds the gesture into the committed state.
    private var liveYaw: Float { yaw + Float(dragTranslation.width) * 0.005 }
    private var livePitch: Float { (pitch + Float(dragTranslation.height) * 0.005).clampedPitch() }
    private var liveDistance: Float { (distance / Float(pinchScale)).clampedDistance() }

    var body: some View {
        MetalSurfaceView(table: table, yaw: liveYaw, pitch: livePitch, distance: liveDistance)
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        yaw += Float(value.translation.width) * 0.005
                        pitch = (pitch + Float(value.translation.height) * 0.005).clampedPitch()
                    }
            )
            .gesture(
                MagnifyGesture()
                    .updating($pinchScale) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        distance = (distance / Float(value.magnification)).clampedDistance()
                    }
            )
            .overlay(alignment: .bottomLeading) { legend }
            .ignoresSafeArea(edges: .bottom)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(table.definition.name).font(.headline)
            axisKey(color: Color(red: 0.95, green: 0.30, blue: 0.25),
                    label: axisLabel(table.definition.xAxis, values: table.xAxis, fallback: "Columns"))
            if !table.yAxis.isEmpty {
                axisKey(color: Color(red: 0.35, green: 0.55, blue: 0.95),
                        label: axisLabel(table.definition.yAxis, values: table.yAxis, fallback: "Rows"))
            }
            axisKey(color: Color(red: 0.30, green: 0.85, blue: 0.40),
                    label: "\(table.definition.unit.isEmpty ? "Value" : table.definition.unit)  \(rangeText(table.minValue, table.maxValue))")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    /// One legend row: a coloured swatch matching the 3D axis line, plus name/unit and range.
    private func axisKey(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 14, height: 3)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func axisLabel(_ axis: AxisDefinition?, values: [Double], fallback: String) -> String {
        let name = axis.map { $0.unit.isEmpty ? $0.name : "\($0.name) (\($0.unit))" } ?? fallback
        guard let first = values.first, let last = values.last else { return name }
        return "\(name)  \(rangeText(first, last))"
    }

    private func rangeText(_ a: Double, _ b: Double) -> String {
        let f: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
        return "\(f(a)) → \(f(b))"
    }
}

private extension Float {
    func clampedPitch() -> Float { Swift.max(-1.4, Swift.min(1.4, self)) }
    func clampedDistance() -> Float { Swift.max(0.8, Swift.min(8, self)) }
}

/// Bridges MetalKit into SwiftUI. `UIViewRepresentable` and `NSViewRepresentable` differ only in
/// method names, so the shared logic lives here and a thin per-platform conformance forwards to it.
struct MetalSurfaceView {
    let table: CalibrationTable
    let yaw: Float
    let pitch: Float
    let distance: Float

    func makeCoordinator() -> Coordinator { Coordinator() }

    fileprivate func makeMTKView(coordinator: Coordinator) -> MTKView {
        let view = MTKView()
        guard let renderer = SurfaceRenderer(mtkView: view) else { return view }
        renderer.update(table: table)
        view.delegate = renderer
        coordinator.renderer = renderer
        return view
    }

    fileprivate func updateMTKView(coordinator: Coordinator) {
        guard let renderer = coordinator.renderer else { return }
        if coordinator.tableID != table.definition.id {
            renderer.update(table: table)
            coordinator.tableID = table.definition.id
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

#if os(macOS)
extension MetalSurfaceView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView { makeMTKView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: MTKView, context: Context) { updateMTKView(coordinator: context.coordinator) }
}
#else
extension MetalSurfaceView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView { makeMTKView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: MTKView, context: Context) { updateMTKView(coordinator: context.coordinator) }
}
#endif
