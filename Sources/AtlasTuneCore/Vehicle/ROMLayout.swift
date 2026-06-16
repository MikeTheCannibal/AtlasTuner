import Foundation

/// A contiguous region of ECU memory to read, and where it lands in the assembled image.
public struct MemoryRegion: Sendable, Equatable {
    public let name: String
    /// Address in the ECU's memory map (e.g. flash base).
    public let address: UInt32
    public let size: Int
    /// Offset of this region within the assembled `BINImage` (usually `address - imageBase`).
    public let imageOffset: Int

    public init(name: String, address: UInt32, size: Int, imageOffset: Int) {
        self.name = name
        self.address = address
        self.size = size
        self.imageOffset = imageOffset
    }
}

/// Describes how to read a full calibration image off a vehicle: the total image size and the
/// memory regions that make it up.
public struct ROMLayout: Sendable {
    public let imageSize: Int
    public let regions: [MemoryRegion]

    public init(imageSize: Int, regions: [MemoryRegion]) {
        self.imageSize = imageSize
        self.regions = regions
    }

    /// PLACEHOLDER S58 / MG1CS049 layout: one 8 MiB calibration region.
    ///
    /// The image *size* matches the real BIN, but `flashBase` (the address the calibration is
    /// mapped at for reads) must be confirmed for the MG1 — it is a structural placeholder. Map it
    /// so region `address - flashBase == imageOffset == 0`, i.e. the read bytes align 1:1 with the
    /// file offsets the XDF/definitions use.
    public static func s58(flashBase: UInt32 = 0x8000_0000) -> ROMLayout {
        let size = 8 * 1024 * 1024
        return ROMLayout(
            imageSize: size,
            regions: [MemoryRegion(name: "Calibration", address: flashBase, size: size, imageOffset: 0)]
        )
    }
}
