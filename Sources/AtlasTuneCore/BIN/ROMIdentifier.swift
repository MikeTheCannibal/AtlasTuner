import Foundation

/// Matches an imported image against the catalogue of known ``DefinitionPackage``s and picks
/// the best fit. This is the automatic step that means a tuner never loads an XDF by hand.
public struct ROMIdentifier: Sendable {
    public let packages: [DefinitionPackage]

    public init(packages: [DefinitionPackage]) {
        self.packages = packages
    }

    public struct Match: Sendable {
        public let package: DefinitionPackage
        public let identity: ROMIdentity
    }

    /// Identify `image`, returning the highest-confidence match if any package is plausible.
    public func identify(_ image: BINImage) -> Match? {
        var best: (score: Double, match: Match)?

        for package in packages {
            let score = confidence(of: package, for: image)
            guard score > 0 else { continue }

            let version = extractVersion(package, image) ?? package.calibrationVersion
            let identity = ROMIdentity(
                family: package.family,
                calibrationVersion: version,
                programIdentifier: nil,
                imageSize: image.size,
                confidence: score
            )
            let match = Match(package: package, identity: identity)
            if best == nil || score > best!.score {
                best = (score, match)
            }
        }
        return best?.match
    }

    /// Confidence in [0, 1]: the fraction of signatures that match, gated on image size.
    func confidence(of package: DefinitionPackage, for image: BINImage) -> Double {
        if !package.expectedImageSizes.isEmpty,
           !package.expectedImageSizes.contains(image.size) {
            return 0
        }
        guard !package.signatures.isEmpty else {
            // Size-only identification when no byte signatures are provided.
            return package.expectedImageSizes.contains(image.size) ? 0.5 : 0
        }
        let matched = package.signatures.reduce(into: 0) { count, sig in
            if matches(sig, in: image) { count += 1 }
        }
        return Double(matched) / Double(package.signatures.count)
    }

    private func matches(_ sig: ROMSignature, in image: BINImage) -> Bool {
        guard let bytes = try? image.readBytes(at: sig.address, length: sig.pattern.count) else {
            return false
        }
        return bytes == sig.pattern
    }

    private func extractVersion(_ package: DefinitionPackage, _ image: BINImage) -> String? {
        guard let field = package.versionField,
              let raw = try? image.readBytes(at: field.address, length: field.length) else {
            return nil
        }
        let printable = raw.prefix { $0 >= 0x20 && $0 < 0x7F }
        let string = String(decoding: printable, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
        return string.isEmpty ? nil : string
    }
}
