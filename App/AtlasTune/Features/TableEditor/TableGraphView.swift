import SwiftUI
import Charts
import AtlasTuneCore

/// 2D graph rendering. For 1D tables it draws a value-vs-axis line; for 2D/3D tables it draws one
/// line per row so the family of curves is visible at a glance.
struct TableGraphView: View {
    let table: CalibrationTable

    private struct Point: Identifiable {
        let id = UUID()
        let series: String
        let x: Double
        let y: Double
    }

    private var points: [Point] {
        var result: [Point] = []
        let xs = table.xAxis.isEmpty ? Array(0..<table.columns).map(Double.init) : table.xAxis
        for row in 0..<table.rows {
            let label = table.yAxis.isEmpty ? "value" : "\(Int(table.yAxis[row]))"
            for column in 0..<table.columns where column < xs.count {
                result.append(Point(series: label, x: xs[column], y: table.values[row][column]))
            }
        }
        return result
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Axis", point.x), y: .value(table.definition.unit, point.y))
                .foregroundStyle(by: .value("Row", point.series))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Axis", point.x), y: .value(table.definition.unit, point.y))
                .foregroundStyle(by: .value("Row", point.series))
                .symbolSize(18)
        }
        .chartLegend(table.yAxis.isEmpty ? .hidden : .visible)
        .padding()
    }
}
