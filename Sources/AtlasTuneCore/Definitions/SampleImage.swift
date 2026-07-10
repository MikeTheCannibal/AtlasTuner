import Foundation

/// Builds a synthetic, fully explorable stand-in for the Phase 1 S58 image so the app can be
/// opened and every table browsed **without a real dump** — which matters because the real 8 MB
/// read embeds a VIN (so it is never shipped) and can't easily be side-loaded onto a Simulator.
///
/// The image is the correct size and carries every identification byte, so it opens as the real
/// bundled package with the correct calibration version. Each table is filled with a smooth,
/// in-range synthetic surface (and its stored axes with monotonic breakpoints), so the spreadsheet,
/// 2D graph, 3D surface and heat map all show real shape rather than flat zeros. It is clearly not
/// a tune — just scaffolding to explore the UI and demo the workflow.
public enum SampleImage {
    /// A ready-to-open synthetic S58 calibration image.
    public static func s58() -> BINImage {
        let package = DefinitionCatalog.phase1.packages.first ?? S58DefinitionPackage.make()
        let size = package.expectedImageSizes.first ?? S58DefinitionPackage.imageSize
        var image = BINImage(bytes: Data(repeating: 0, count: size), byteOrder: .littleEndian)

        // Fill tables first, then stamp identification bytes last so identification always wins
        // even if a table's data region happens to overlap a signature address.
        for definition in package.tables {
            fill(definition, into: &image)
        }
        for signature in package.signatures {
            try? image.writeBytes(signature.pattern, at: signature.address)
        }
        if let field = package.versionField {
            let banner = Array(package.calibrationVersion.utf8).prefix(field.length)
            try? image.writeBytes(Array(banner), at: field.address)
        }
        return image
    }

    // MARK: Synthetic content

    private static func fill(_ definition: TableDefinition, into image: inout BINImage) {
        writeAxisRamp(definition.xAxis, into: &image)
        writeAxisRamp(definition.yAxis, into: &image)

        let (lo, hi) = displayRange(for: definition)
        for row in 0..<definition.rows {
            for column in 0..<definition.columns {
                let u = definition.columns > 1 ? Double(column) / Double(definition.columns - 1) : 0
                let v = definition.rows > 1 ? Double(row) / Double(definition.rows - 1) : 0
                // A gentle diagonal ridge: rises toward one corner with a soft bump, so surfaces
                // and heat maps read as recognisably map-like rather than a flat plane.
                let t = 0.15 + 0.7 * (0.5 * (u + v) + 0.15 * sin(u * .pi) * sin(v * .pi))
                let value = lo + (hi - lo) * min(1, max(0, t))
                let offset = definition.address + (row * definition.columns + column) * definition.dataType.byteWidth
                try? image.writeRaw(definition.scaling.raw(fromDisplay: value), type: definition.dataType, at: offset)
            }
        }
    }

    /// Write a monotonic increasing raw ramp into a stored axis so 2D graphs have a sensible X.
    private static func writeAxisRamp(_ axis: AxisDefinition?, into image: inout BINImage) {
        guard let axis, case let .stored(address, dataType, _) = axis.source, axis.count > 0 else { return }
        for i in 0..<axis.count {
            let offset = address + i * dataType.byteWidth
            try? image.writeRaw(Double(i), type: dataType, at: offset)
        }
    }

    /// A representable display range to fill a table across: its declared safe range (inset a
    /// touch so edge clamping doesn't flatten it), else a mid-band derived from what the raw type
    /// can actually hold under the table's scaling.
    private static func displayRange(for definition: TableDefinition) -> (Double, Double) {
        if let range = definition.valueRange, range.upperBound > range.lowerBound {
            let inset = (range.upperBound - range.lowerBound) * 0.05
            return (range.lowerBound + inset, range.upperBound - inset)
        }
        let scaling = definition.scaling
        if let raw = definition.dataType.rawRange {
            let a = scaling.display(fromRaw: raw.lowerBound + (raw.upperBound - raw.lowerBound) * 0.1)
            let b = scaling.display(fromRaw: raw.lowerBound + (raw.upperBound - raw.lowerBound) * 0.6)
            return (min(a, b), max(a, b))
        }
        // float32: no bounded raw range — pick a modest span in display units.
        let a = scaling.display(fromRaw: 0)
        let b = scaling.display(fromRaw: 100)
        return (min(a, b), max(a, b))
    }
}
