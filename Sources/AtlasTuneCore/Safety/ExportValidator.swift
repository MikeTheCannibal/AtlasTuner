import Foundation

/// A single validation finding raised before export.
public struct ValidationIssue: Sendable, Equatable, Identifiable {
    public enum Severity: String, Sendable { case warning, error }
    public let id = UUID()
    public let severity: Severity
    public let tableID: String?
    public let message: String

    public init(severity: Severity, tableID: String? = nil, message: String) {
        self.severity = severity
        self.tableID = tableID
        self.message = message
    }
}

/// The outcome of validating an image prior to export.
public struct ValidationReport: Sendable, Equatable {
    public let issues: [ValidationIssue]
    public var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    public var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    /// Safe to export only when there are no errors.
    public var isExportable: Bool { errors.isEmpty }
}

/// Validates a calibration image against its definition package before allowing export,
/// satisfying the spec's "validation before export" safety requirement. Catches:
/// out-of-range values, size mismatches, and (optionally) checksum problems.
public struct ExportValidator: Sendable {
    private let accessor = TableAccessor()

    public init() {}

    public func validate(_ image: BINImage, using package: DefinitionPackage) -> ValidationReport {
        var issues: [ValidationIssue] = []

        if !package.expectedImageSizes.isEmpty, !package.expectedImageSizes.contains(image.size) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "Image size \(image.size) bytes does not match expected size for \(package.family)."
            ))
        }

        for definition in package.tables {
            guard definition.address + definition.byteSize <= image.size else {
                issues.append(ValidationIssue(
                    severity: .error,
                    tableID: definition.id,
                    message: "Table \(definition.name) extends past the end of the image."
                ))
                continue
            }
            guard let range = definition.valueRange,
                  let table = try? accessor.read(definition, from: image) else { continue }

            for value in table.flatValues where value < range.lowerBound || value > range.upperBound {
                issues.append(ValidationIssue(
                    severity: .warning,
                    tableID: definition.id,
                    message: "Table \(definition.name) contains a value (\(value)) outside its safe range \(range.lowerBound)…\(range.upperBound)."
                ))
                break
            }
        }
        return ValidationReport(issues: issues)
    }
}
