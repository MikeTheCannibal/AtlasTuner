import Foundation

/// The result of identifying an imported BIN against the known ROM families.
///
/// Atlas Tune performs identification automatically; the tuner never selects a
/// definition file by hand. A confident identity is what unlocks a matching
/// ``DefinitionPackage``.
public struct ROMIdentity: Codable, Sendable, Hashable {
    /// ROM family, e.g. "S58 / MG1CS003".
    public var family: String
    /// Calibration / software version string extracted from the image.
    public var calibrationVersion: String
    /// Hardware or program identifier when available (e.g. I-Level / SW number).
    public var programIdentifier: String?
    /// Size of the imported image in bytes.
    public var imageSize: Int
    /// Confidence in [0, 1]. 1.0 means every identification signature matched.
    public var confidence: Double

    public init(
        family: String,
        calibrationVersion: String,
        programIdentifier: String? = nil,
        imageSize: Int,
        confidence: Double
    ) {
        self.family = family
        self.calibrationVersion = calibrationVersion
        self.programIdentifier = programIdentifier
        self.imageSize = imageSize
        self.confidence = confidence
    }

    /// Identity used when no known family matches the image.
    public static func unknown(imageSize: Int) -> ROMIdentity {
        ROMIdentity(
            family: "Unknown",
            calibrationVersion: "Unknown",
            programIdentifier: nil,
            imageSize: imageSize,
            confidence: 0
        )
    }

    public var isIdentified: Bool { confidence > 0 }
}
