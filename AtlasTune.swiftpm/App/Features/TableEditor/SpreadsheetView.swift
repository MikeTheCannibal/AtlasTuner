import SwiftUI
import AtlasTuneCore

/// The traditional tuner spreadsheet: axis headers, value cells coloured by magnitude, and an
/// optional live heat-map overlay from the active-cell tracker. Cells are tap/drag selectable.
struct SpreadsheetView: View {
    let table: CalibrationTable
    @Binding var selection: CellRegion
    var heatMap: [[Double]]?

    private var range: ClosedRange<Double> {
        let lo = table.minValue, hi = table.maxValue
        return lo < hi ? lo...hi : lo...(lo + 1)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                if !table.xAxis.isEmpty {
                    GridRow {
                        corner
                        ForEach(Array(table.xAxis.enumerated()), id: \.offset) { _, x in
                            axisHeader(x)
                        }
                    }
                }
                ForEach(0..<table.rows, id: \.self) { row in
                    GridRow {
                        if !table.yAxis.isEmpty, row < table.yAxis.count {
                            axisHeader(table.yAxis[row])
                        }
                        ForEach(0..<table.columns, id: \.self) { column in
                            cell(row: row, column: column)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private var corner: some View {
        Text(table.definition.xAxis?.unit ?? "")
            .font(.caption2).foregroundStyle(.secondary)
            .frame(minWidth: 56, minHeight: 32)
    }

    private func axisHeader(_ value: Double) -> some View {
        Text(value, format: .number.precision(.fractionLength(0)))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 56, minHeight: 32)
            .background(Color(.secondarySystemBackground))
    }

    private func cell(row: Int, column: Int) -> some View {
        let value = table.values[row][column]
        let selected = selection.rows.contains(row) && selection.columns.contains(column)
        return Text(value, format: .number.precision(.fractionLength(table.definition.scaling.decimals)))
            .font(.callout.monospacedDigit())
            .frame(minWidth: 56, minHeight: 32)
            .background(cellBackground(value: value, row: row, column: column))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = CellRegion(row: row, column: column) }
    }

    private func cellBackground(value: Double, row: Int, column: Int) -> some View {
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        let base = Color(hue: 0.6 - 0.6 * t, saturation: 0.55, brightness: 0.95) // blue→red
        let heat = heatMap?[safe: row]?[safe: column] ?? 0
        return base.opacity(0.35 + 0.4 * t)
            .overlay(Color.orange.opacity(heat * 0.5))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
