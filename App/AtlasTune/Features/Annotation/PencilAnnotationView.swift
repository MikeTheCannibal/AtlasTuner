import SwiftUI
import PencilKit

/// A PencilKit overlay so tuners can mark up maps and logs directly with Apple Pencil Pro:
/// circle a region, jot a note, annotate a trouble area. Strokes are kept per-table so notes
/// persist with the calibration.
///
/// Apple Pencil Pro features (barrel roll, squeeze, hover) are surfaced natively by `PKCanvasView`
/// and the tool picker; this wrapper just hosts the canvas and reports drawing changes upward.
struct PencilAnnotationView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .pencilOnly // finger gestures stay free for pan/zoom
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        canvas.drawing = drawing

        let picker = PKToolPicker()
        picker.addObserver(canvas)
        picker.setVisible(isActive, forFirstResponder: canvas)
        context.coordinator.toolPicker = picker
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.isUserInteractionEnabled = isActive
        context.coordinator.toolPicker?.setVisible(isActive, forFirstResponder: canvas)
        if isActive { canvas.becomeFirstResponder() }
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private let parent: PencilAnnotationView
        var toolPicker: PKToolPicker?

        init(_ parent: PencilAnnotationView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

/// Convenience modifier that layers annotation over any editor surface.
struct AnnotatableModifier: ViewModifier {
    @State private var drawing = PKDrawing()
    @State private var annotating = false

    func body(content: Content) -> some View {
        content
            .overlay { PencilAnnotationView(drawing: $drawing, isActive: annotating) }
            .overlay(alignment: .topTrailing) {
                Button {
                    annotating.toggle()
                } label: {
                    Image(systemName: annotating ? "pencil.circle.fill" : "pencil.circle")
                        .font(.title2)
                }
                .padding(8)
            }
    }
}

extension View {
    /// Make any editor surface markable with Apple Pencil.
    func annotatable() -> some View { modifier(AnnotatableModifier()) }
}
