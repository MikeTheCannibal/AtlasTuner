import Foundation

/// An immutable snapshot of a calibration at a point in time. Every save creates one, forming
/// a tree (Stock → Revision 1 → E30 Test → …) via `parentID`.
public struct Revision: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var parentID: UUID?
    public var name: String
    public var notes: String
    public let timestamp: Date
    /// Full image bytes for this snapshot.
    public var imageData: Data
    public var byteOrder: ByteOrder
    /// CRC32 of `imageData` for fast equality / corruption checks.
    public let checksum: UInt32

    public init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        name: String,
        notes: String = "",
        timestamp: Date = Date(),
        image: BINImage
    ) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.notes = notes
        self.timestamp = timestamp
        self.imageData = image.bytes
        self.byteOrder = image.byteOrder
        self.checksum = CRC32.checksum(image.bytes)
    }

    /// Reconstruct the `BINImage` this revision captured.
    public var image: BINImage {
        BINImage(bytes: imageData, byteOrder: byteOrder)
    }
}
