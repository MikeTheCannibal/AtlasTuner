import Foundation

/// A portable bundle capturing a project's full revision history plus identifying metadata.
/// This is the "Revision Package" export format: a single Codable archive that can be re-imported
/// to restore the entire editing history.
public struct RevisionPackage: Codable, Sendable {
    public var formatVersion: Int
    public var family: String
    public var calibrationVersion: String
    public var definitionPackageID: String
    public var revisions: [Revision]
    public var exportedAt: Date

    public init(
        formatVersion: Int = 1,
        family: String,
        calibrationVersion: String,
        definitionPackageID: String,
        revisions: [Revision],
        exportedAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.family = family
        self.calibrationVersion = calibrationVersion
        self.definitionPackageID = definitionPackageID
        self.revisions = revisions
        self.exportedAt = exportedAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> RevisionPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RevisionPackage.self, from: data)
    }
}
