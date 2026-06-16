import Foundation

/// Produces the three export artifacts described in the spec. Atlas Tune never flashes — it
/// exports a clean BIN (optionally checksum-corrected) for an external flashing tool, plus the
/// revision package and metadata report.
public struct CalibrationExporter: Sendable {
    public enum Format: Sendable {
        case bin
        case revisionPackage
        case metadataReport
    }

    public init() {}

    /// Export a flashable BIN. If a checksum strategy is supplied, protected blocks are
    /// recomputed so the file is valid for the target ECU.
    public func exportBIN(_ image: BINImage, checksum: ChecksumStrategy? = nil) throws -> Data {
        let corrected = try checksum?.correct(image) ?? image
        return corrected.bytes
    }

    public func exportRevisionPackage(_ tree: RevisionTree, identity: ROMIdentity, packageID: String) throws -> Data {
        let package = RevisionPackage(
            family: identity.family,
            calibrationVersion: identity.calibrationVersion,
            definitionPackageID: packageID,
            revisions: tree.all
        )
        return try package.encoded()
    }

    public func exportMetadataReport(_ report: MetadataReport) -> Data {
        report.data()
    }
}
