import Foundation

/// Bridges a ``TableDefinition`` and a ``BINImage``: reads bytes into a ``CalibrationTable``
/// of engineering values, and writes an edited table back into a copy of the image.
public struct TableAccessor: Sendable {
    public init() {}

    // MARK: Read

    /// Decode the table described by `definition` out of `image`.
    public func read(_ definition: TableDefinition, from image: BINImage) throws -> CalibrationTable {
        let x = try resolveAxis(definition.xAxis, from: image)
        let y = try resolveAxis(definition.yAxis, from: image)

        var values = [[Double]]()
        values.reserveCapacity(definition.rows)
        let width = definition.dataType.byteWidth

        for row in 0..<definition.rows {
            var rowValues = [Double]()
            rowValues.reserveCapacity(definition.columns)
            for column in 0..<definition.columns {
                let index = row * definition.columns + column
                let offset = definition.address + index * width
                let raw = try image.readRaw(definition.dataType, at: offset)
                rowValues.append(definition.scaling.display(fromRaw: raw))
            }
            values.append(rowValues)
        }

        return CalibrationTable(definition: definition, xAxis: x, yAxis: y, values: values)
    }

    // MARK: Write

    /// Write `table`'s values back into a copy of `image`, applying inverse scaling, range
    /// clamping and integer rounding. Axes are written too when they are stored in the image.
    public func write(_ table: CalibrationTable, into image: BINImage) throws -> BINImage {
        var output = image
        let definition = table.definition
        let width = definition.dataType.byteWidth

        for row in 0..<definition.rows {
            for column in 0..<definition.columns {
                let index = row * definition.columns + column
                let offset = definition.address + index * width
                var display = table.values[row][column]
                if let range = definition.valueRange {
                    display = min(max(display, range.lowerBound), range.upperBound)
                }
                let raw = definition.scaling.raw(fromDisplay: display)
                try output.writeRaw(raw, type: definition.dataType, at: offset)
            }
        }

        try writeAxis(definition.xAxis, values: table.xAxis, into: &output)
        try writeAxis(definition.yAxis, values: table.yAxis, into: &output)
        return output
    }

    // MARK: Axes

    private func resolveAxis(_ axis: AxisDefinition?, from image: BINImage) throws -> [Double] {
        guard let axis else { return [] }
        switch axis.source {
        case .fixed(let values):
            return values
        case .stored(let address, let dataType, let scaling):
            return try (0..<axis.count).map { i in
                let raw = try image.readRaw(dataType, at: address + i * dataType.byteWidth)
                return scaling.display(fromRaw: raw)
            }
        }
    }

    private func writeAxis(_ axis: AxisDefinition?, values: [Double], into image: inout BINImage) throws {
        guard let axis, case let .stored(address, dataType, scaling) = axis.source else { return }
        for (i, display) in values.enumerated() where i < axis.count {
            let raw = scaling.raw(fromDisplay: display)
            try image.writeRaw(raw, type: dataType, at: address + i * dataType.byteWidth)
        }
    }
}
