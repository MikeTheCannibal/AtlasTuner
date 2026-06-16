import Foundation

/// A single chunked read request: read `length` bytes from `address`, placing them at
/// `imageOffset` in the assembled image.
public struct ROMReadChunk: Sendable, Equatable {
    public let address: UInt32
    public let length: Int
    public let imageOffset: Int
}

/// Splits a `ROMLayout` into fixed-size chunks suitable for UDS ReadMemoryByAddress, so the read
/// can stream with progress and survive per-request size limits. Pure and deterministic.
public struct ROMReadPlan: Sendable {
    public let chunks: [ROMReadChunk]
    public let totalBytes: Int

    public init(layout: ROMLayout, chunkSize: Int = 0x400) {
        let size = max(1, chunkSize)
        var chunks: [ROMReadChunk] = []
        var total = 0
        for region in layout.regions {
            var offset = 0
            while offset < region.size {
                let length = min(size, region.size - offset)
                chunks.append(ROMReadChunk(
                    address: region.address &+ UInt32(offset),
                    length: length,
                    imageOffset: region.imageOffset + offset
                ))
                offset += length
                total += length
            }
        }
        self.chunks = chunks
        self.totalBytes = total
    }
}

/// Accumulates chunk responses into the final image, tracking how many bytes have arrived.
public struct ROMAssembler: Sendable {
    public private(set) var bytes: [UInt8]
    public private(set) var bytesReceived: Int = 0
    public let totalBytes: Int

    public init(totalBytes: Int) {
        self.totalBytes = totalBytes
        self.bytes = [UInt8](repeating: 0, count: totalBytes)
    }

    /// Place a chunk's data at its image offset.
    public mutating func place(_ data: [UInt8], at imageOffset: Int) {
        guard imageOffset >= 0, imageOffset + data.count <= bytes.count else { return }
        for (i, byte) in data.enumerated() { bytes[imageOffset + i] = byte }
        bytesReceived += data.count
    }

    public var progress: Double { totalBytes > 0 ? Double(bytesReceived) / Double(totalBytes) : 0 }
    public var isComplete: Bool { bytesReceived >= totalBytes }

    public func image(byteOrder: ByteOrder = .littleEndian) -> BINImage {
        BINImage(bytes: Data(bytes), byteOrder: byteOrder)
    }
}
