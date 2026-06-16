import Foundation

/// A single byte pattern that, when found at a given address, contributes evidence that an
/// image belongs to a particular ROM family/version.
public struct ROMSignature: Codable, Sendable, Hashable {
    public var address: Int
    /// Expected bytes at `address`.
    public var pattern: [UInt8]
    /// Human description for diagnostics ("MG1 calibration block header").
    public var label: String

    public init(address: Int, pattern: [UInt8], label: String = "") {
        self.address = address
        self.pattern = pattern
        self.label = label
    }

    /// Build a signature from an ASCII string (e.g. a version banner).
    public init(address: Int, ascii: String, label: String = "") {
        self.address = address
        self.pattern = Array(ascii.utf8)
        self.label = label
    }
}

/// Describes where to read a printable version/identifier string from an image.
public struct VersionField: Codable, Sendable, Hashable {
    public var address: Int
    public var length: Int

    public init(address: Int, length: Int) {
        self.address = address
        self.length = length
    }
}
