import Foundation

/// A human-readable report describing a calibration and its changes from stock, emitted as one
/// of the export formats. Plain text keeps it portable and diff-friendly.
public struct MetadataReport: Sendable {
    public let identity: ROMIdentity
    public let package: DefinitionPackage
    public let difference: CalibrationDifference?
    public let generatedAt: Date

    public init(
        identity: ROMIdentity,
        package: DefinitionPackage,
        difference: CalibrationDifference? = nil,
        generatedAt: Date = Date()
    ) {
        self.identity = identity
        self.package = package
        self.difference = difference
        self.generatedAt = generatedAt
    }

    public func text() -> String {
        var lines: [String] = []
        lines.append("Atlas Tune — Calibration Metadata Report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: generatedAt))")
        lines.append("")
        lines.append("ROM Family:        \(identity.family)")
        lines.append("Calibration:       \(identity.calibrationVersion)")
        lines.append("Image Size:        \(identity.imageSize) bytes")
        lines.append("Definition:        \(package.id)")
        lines.append("Tables Defined:    \(package.tables.count)")
        lines.append("")

        if let difference {
            lines.append("Changes vs comparison image:")
            if difference.isIdentical {
                lines.append("  (no changes)")
            } else {
                lines.append("  Changed tables: \(difference.changedTables.count)")
                lines.append("  Changed cells:  \(difference.totalChangedCells)")
                lines.append("")
                for diff in difference.changedTables.sorted(by: { $0.category < $1.category }) {
                    lines.append("  • [\(diff.category.displayName)] \(diff.tableName): "
                                 + "\(diff.changedCount) cells, max Δ \(String(format: "%.3f", diff.maxAbsoluteDelta))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    public func data() -> Data { Data(text().utf8) }
}
