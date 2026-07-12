import SwiftUI
import AtlasTuneCore

/// The quick-adjust bar under the grid: a live summary of the current selection and big,
/// touch-friendly controls for the common tune edits — nudge up/down by a step, scale by a
/// percent, set an absolute value, and smooth/interpolate/flatten. Covers the engine's full
/// operation set (set/add/subtract/multiply/divide/percent/interpolate/smooth/flatten).
struct EditToolbar: View {
    /// Stats for the current selection, shown so the tuner always knows what they're about to change.
    let stats: SelectionStats
    /// One display-unit step (10^-decimals), used by the ± nudge buttons.
    let step: Double
    let apply: (EditOperation) -> Void

    @State private var setValue: Double = 0
    @State private var percent: Double = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summary
            HStack(spacing: 8) {
                nudgeGroup
                Divider().frame(height: 34)
                setGroup
                Divider().frame(height: 34)
                shapeGroup
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Selection summary

    private var summary: some View {
        HStack(spacing: 12) {
            Label("\(stats.cellCount) cell\(stats.cellCount == 1 ? "" : "s")", systemImage: "square.grid.3x3")
                .font(.caption.bold())
            if stats.cellCount > 0 {
                stat("min", stats.min)
                stat("avg", stats.mean)
                stat("max", stats.max)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2)
            Text(value, format: .number.precision(.fractionLength(stats.decimals)))
                .font(.caption.monospacedDigit().bold()).foregroundStyle(.primary)
        }
    }

    // MARK: Groups

    private var nudgeGroup: some View {
        HStack(spacing: 6) {
            bigButton("−\(pct)%", "arrow.down") { .percentChange(-percent) }
            bigButton("−", "minus") { .subtract(step) }
            bigButton("+", "plus") { .add(step) }
            bigButton("+\(pct)%", "arrow.up") { .percentChange(percent) }
            Stepper("", value: $percent, in: 0.5...25, step: 0.5).labelsHidden()
                .help("Percent step")
        }
    }

    private var setGroup: some View {
        HStack(spacing: 6) {
            TextField("Value", value: $setValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 84)
            #if os(iOS)
                .keyboardType(.numbersAndPunctuation)
            #endif
            bigButton("Set", "equal") { .set(setValue) }
        }
    }

    private var shapeGroup: some View {
        HStack(spacing: 6) {
            bigButton("Interp", "arrow.left.and.right") { .interpolate(.both) }
            bigButton("Smooth", "wand.and.stars") { .smooth(passes: 1) }
            bigButton("Flatten", "rectangle.compress.vertical") { .flatten }
        }
    }

    private var pct: String { percent.formatted(.number.precision(.fractionLength(percent == percent.rounded() ? 0 : 1))) }

    private func bigButton(_ title: String, _ symbol: String, _ make: @escaping () -> EditOperation) -> some View {
        Button { apply(make()) } label: {
            VStack(spacing: 1) {
                Image(systemName: symbol).font(.body)
                Text(title).font(.caption2)
            }
            .frame(minWidth: 52, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(stats.cellCount == 0)
        .help(title)
    }
}

/// Aggregate stats over the current selection, for the adjust bar's readout.
struct SelectionStats {
    let cellCount: Int
    let min: Double
    let mean: Double
    let max: Double
    let decimals: Int

    static func of(_ region: CellRegion, in table: CalibrationTable) -> SelectionStats {
        let clamped = region.clamped(to: table)
        var values: [Double] = []
        values.reserveCapacity(clamped.cellCount)
        for r in clamped.rows where r < table.rows {
            for c in clamped.columns where c < table.columns {
                values.append(table.values[r][c])
            }
        }
        guard !values.isEmpty else {
            return SelectionStats(cellCount: 0, min: 0, mean: 0, max: 0, decimals: table.definition.scaling.decimals)
        }
        return SelectionStats(
            cellCount: values.count,
            min: values.min() ?? 0,
            mean: values.reduce(0, +) / Double(values.count),
            max: values.max() ?? 0,
            decimals: table.definition.scaling.decimals
        )
    }
}
