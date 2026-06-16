import Foundation

/// Abstraction over a ROM family's checksum/CRC scheme. BMW MG1 images contain several
/// protected blocks whose checksums must be corrected after editing; the concrete strategy is
/// family-specific, so the engine talks to this protocol and the definition layer supplies it.
public protocol ChecksumStrategy: Sendable {
    /// Verify all protected regions; returns the regions that fail.
    func verify(_ image: BINImage) -> [ChecksumRegion]
    /// Return a corrected copy of `image` with all protected checksums recomputed.
    func correct(_ image: BINImage) throws -> BINImage
}

/// Describes one checksum-protected region.
public struct ChecksumRegion: Sendable, Equatable {
    public let name: String
    public let range: Range<Int>
    /// Where the stored checksum lives.
    public let storedAt: Int
    public let dataType: DataType

    public init(name: String, range: Range<Int>, storedAt: Int, dataType: DataType = .uint32) {
        self.name = name
        self.range = range
        self.storedAt = storedAt
        self.dataType = dataType
    }
}

/// A simple CRC32-over-region strategy, suitable as a default and for tests. Real S58 blocks
/// use a documented polynomial/seed; those are slotted in via the definition package without
/// touching call sites.
public struct CRC32ChecksumStrategy: ChecksumStrategy {
    public let regions: [ChecksumRegion]

    public init(regions: [ChecksumRegion]) {
        self.regions = regions
    }

    public func verify(_ image: BINImage) -> [ChecksumRegion] {
        regions.filter { region in
            guard let bytes = try? image.readBytes(at: region.range.lowerBound, length: region.range.count),
                  let stored = try? image.readRaw(region.dataType, at: region.storedAt) else { return true }
            return UInt32(stored) != CRC32.checksum(bytes)
        }
    }

    public func correct(_ image: BINImage) throws -> BINImage {
        var output = image
        for region in regions {
            let bytes = try output.readBytes(at: region.range.lowerBound, length: region.range.count)
            let crc = CRC32.checksum(bytes)
            try output.writeRaw(Double(crc), type: region.dataType, at: region.storedAt)
        }
        return output
    }
}
