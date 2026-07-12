import SwiftUI
import AtlasTuneCore

/// The tuner spreadsheet: axis headers, magnitude-coloured value cells and a live heat-map overlay.
/// Touch-first selection like the established table editors — tap a cell, **drag to sweep a
/// rectangle**, tap a column/row header to take the whole column/row, tap the corner for the whole
/// table. Fixed cell metrics make drag hit-testing exact.
struct SpreadsheetView: View {
    let table: CalibrationTable
    @Binding var selection: CellRegion
    var heatMap: [[Double]]?

    // Base metrics; a drag location still maps deterministically onto a cell because every
    // metric scales by the same zoom factor.
    private static let baseCellW: CGFloat = 66
    private static let baseCellH: CGFloat = 42
    private static let baseHeaderW: CGFloat = 60
    private static let baseHeaderH: CGFloat = 38

    /// Committed pinch zoom (0.4 = whole big table at a glance … 2.5 = large readable cells).
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    /// Live zoom = committed zoom × the in-flight pinch, so the grid scales under the fingers.
    private var liveZoom: CGFloat { (zoom * pinch).clampedZoom() }
    private var cellW: CGFloat { Self.baseCellW * liveZoom }
    private var cellH: CGFloat { Self.baseCellH * liveZoom }
    private var headerW: CGFloat { Self.baseHeaderW * liveZoom }
    private var headerH: CGFloat { Self.baseHeaderH * liveZoom }
    /// Font sizes track the zoom so text stays proportional and crisp (no raster scaling).
    private var valueFontSize: CGFloat { 14 * liveZoom }
    private var headerFontSize: CGFloat { 11 * liveZoom }

    private var hasColHeader: Bool { !table.xAxis.isEmpty }
    private var hasRowHeader: Bool { !table.yAxis.isEmpty }

    private var range: ClosedRange<Double> {
        let lo = table.minValue, hi = table.maxValue
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            grid
                .coordinateSpace(name: "grid")
                .gesture(sweep)
                .padding(8)
        }
        .simultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in zoom = (zoom * value.magnification).clampedZoom() }
        )
        .overlay(alignment: .bottomTrailing) { zoomBadge }
    }

    /// Small transient control: current zoom + reset, so trackpad users aren't stuck.
    @ViewBuilder private var zoomBadge: some View {
        if abs(liveZoom - 1) > 0.01 {
            Button {
                withAnimation(.snappy) { zoom = 1 }
            } label: {
                Label("\(Int((liveZoom * 100).rounded()))%", systemImage: "arrow.counterclockwise")
                    .font(.caption.monospacedDigit())
            }
            .buttonStyle(.bordered)
            .padding(10)
            .help("Reset zoom to 100%")
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            if hasColHeader {
                HStack(spacing: 0) {
                    if hasRowHeader { cornerHeader }
                    ForEach(Array(table.xAxis.enumerated()), id: \.offset) { index, x in
                        columnHeader(x, column: index)
                    }
                }
            }
            ForEach(0..<table.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    if hasRowHeader, row < table.yAxis.count {
                        rowHeader(table.yAxis[row], row: row)
                    }
                    ForEach(0..<table.columns, id: \.self) { column in
                        cell(row: row, column: column)
                    }
                }
            }
        }
    }

    // MARK: Cells

    private func cell(row: Int, column: Int) -> some View {
        let value = table.values[row][column]
        let selected = selection.rows.contains(row) && selection.columns.contains(column)
        let heat = heatMap?[safe: row]?[safe: column] ?? 0
        return Text(value, format: .number.precision(.fractionLength(table.definition.scaling.decimals)))
            .font(.system(size: valueFontSize, weight: selected ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(width: cellW, height: cellH)
            .background(heatColor(value))
            .overlay(Color.orange.opacity(heat * 0.55))          // active-cell tracker overlay
            .overlay { if selected { Color.accentColor.opacity(0.28) } }
            .overlay { if selected { selectionBorder(row: row, column: column) } }
            .border(Color.primary.opacity(0.06), width: 0.5)
    }

    /// Outline only the edges of the selected rectangle so it reads as one block.
    private func selectionBorder(row: Int, column: Int) -> some View {
        let r = selection.rows, c = selection.columns
        return ZStack {
            if row == r.lowerBound { edge(.top) }
            if row == r.upperBound - 1 { edge(.bottom) }
            if column == c.lowerBound { edge(.leading) }
            if column == c.upperBound - 1 { edge(.trailing) }
        }
    }

    private func edge(_ side: Edge) -> some View {
        let w: CGFloat = 2.5
        return Rectangle().fill(Color.accentColor)
            .frame(width: side == .leading || side == .trailing ? w : cellW,
                   height: side == .top || side == .bottom ? w : cellH)
            .frame(width: cellW, height: cellH, alignment: alignment(for: side))
    }

    private func alignment(for side: Edge) -> Alignment {
        switch side {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    // MARK: Headers (whole column / row / table selection)

    private var cornerHeader: some View {
        Button { selection = CellRegion.all(table) } label: {
            Text(table.definition.xAxis?.unit ?? "")
                .font(.system(size: headerFontSize, weight: .bold)).foregroundStyle(.secondary)
                .frame(width: headerW, height: headerH)
                .background(Color.secondaryBackground)
        }
        .buttonStyle(.plain)
        .help("Select whole table")
    }

    private func columnHeader(_ value: Double, column: Int) -> some View {
        Button { selection = CellRegion(rows: 0..<table.rows, columns: column..<(column + 1)) } label: {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.system(size: headerFontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: cellW, height: headerH)
                .background(selection.columns.contains(column) ? Color.accentColor.opacity(0.2) : Color.secondaryBackground)
        }
        .buttonStyle(.plain)
    }

    private func rowHeader(_ value: Double, row: Int) -> some View {
        Button { selection = CellRegion(rows: row..<(row + 1), columns: 0..<table.columns) } label: {
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.system(size: headerFontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: headerW, height: cellH)
                .background(selection.rows.contains(row) ? Color.accentColor.opacity(0.2) : Color.secondaryBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: Colour

    /// Classic tuning heat ramp: green (low) → yellow → red (high), so gradients read at a glance.
    private func heatColor(_ value: Double) -> Color {
        let t = ((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped01()
        return Color(hue: 0.33 * (1 - t), saturation: 0.66, brightness: 0.92)
            .opacity(0.30 + 0.35 * t)
    }

    // MARK: Sweep-to-select

    private var sweep: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
            .onChanged { g in
                let a = cellAt(g.startLocation)
                let b = cellAt(g.location)
                selection = CellRegion(
                    rows: min(a.row, b.row)..<(max(a.row, b.row) + 1),
                    columns: min(a.column, b.column)..<(max(a.column, b.column) + 1)
                ).clamped(to: table)
            }
    }

    /// Map a point in the grid coordinate space to a cell index, clamped to the value area.
    private func cellAt(_ point: CGPoint) -> (row: Int, column: Int) {
        let x0 = hasRowHeader ? headerW : 0
        let y0 = hasColHeader ? headerH : 0
        let column = Int((point.x - CGFloat(x0)) / cellW)
        let row = Int((point.y - CGFloat(y0)) / cellH)
        return (min(max(row, 0), table.rows - 1), min(max(column, 0), table.columns - 1))
    }
}

private extension Double {
    func clamped01() -> Double { Swift.min(1, Swift.max(0, self)) }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


private extension CGFloat {
    func clampedZoom() -> CGFloat { Swift.max(0.4, Swift.min(2.5, self)) }
}
