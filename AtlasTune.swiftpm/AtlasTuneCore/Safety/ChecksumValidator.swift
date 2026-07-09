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

/// Data-driven strategy executing a `ChecksumScheme` from the definition package: any CRC-16/32
/// family, multi-range blocks, and per-block stored byte order.
public struct SchemeChecksumStrategy: ChecksumStrategy {
    public let scheme: ChecksumScheme

    public init(scheme: ChecksumScheme) {
        self.scheme = scheme
    }

    public func verify(_ image: BINImage) -> [ChecksumRegion] {
        scheme.blocks.compactMap { block in
            guard let computed = try? computed(block, in: image),
                  let stored = try? stored(block, in: image),
                  computed == stored else { return region(for: block) }
            return nil
        }
    }

    public func correct(_ image: BINImage) throws -> BINImage {
        var output = image
        for block in scheme.blocks {
            let value = try computed(block, in: output)
            let width = block.storedType.byteWidth
            var bytes = (0..<width).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
            if (block.storedByteOrder ?? output.byteOrder) == .bigEndian { bytes.reverse() }
            try output.writeBytes(bytes, at: block.storedAt)
        }
        return output
    }

    private func computed(_ block: ChecksumBlock, in image: BINImage) throws -> UInt32 {
        var engine = ParametricCRC(block.algorithm.parameters)
        for span in block.ranges {
            engine.update(try image.readBytes(at: span.start, length: span.length))
        }
        return engine.value
    }

    private func stored(_ block: ChecksumBlock, in image: BINImage) throws -> UInt32 {
        var bytes = try image.readBytes(at: block.storedAt, length: block.storedType.byteWidth)
        if (block.storedByteOrder ?? image.byteOrder) == .bigEndian { bytes.reverse() }
        return bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }

    /// Failing blocks are reported over their first protected range.
    private func region(for block: ChecksumBlock) -> ChecksumRegion {
        ChecksumRegion(
            name: block.name,
            range: block.ranges.first?.range ?? 0..<0,
            storedAt: block.storedAt,
            dataType: block.storedType
        )
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
