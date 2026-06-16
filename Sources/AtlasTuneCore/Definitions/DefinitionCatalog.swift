import Foundation

/// The registry of every ``DefinitionPackage`` Atlas Tune ships with. The app asks the catalog
/// to identify an imported image; the catalog never exposes XDF/XML or addresses to the UI.
public struct DefinitionCatalog: Sendable {
    public let packages: [DefinitionPackage]
    private let identifier: ROMIdentifier

    public init(packages: [DefinitionPackage]) {
        self.packages = packages
        self.identifier = ROMIdentifier(packages: packages)
    }

    /// The default Phase 1 catalog: S58 only.
    ///
    /// Prefers the full definition package generated from the MHD+ XDF (1300+ tables, real
    /// addresses), bundled as a JSON resource. Falls back to the compact programmatic package if
    /// the resource is unavailable.
    public static let phase1: DefinitionCatalog = {
        if let bundled = DefinitionPackage.bundled(named: "s58_mg1cs049") {
            return DefinitionCatalog(packages: [bundled])
        }
        return DefinitionCatalog(packages: [S58DefinitionPackage.make()])
    }()

    /// Identify an image and return the best-matching package plus identity, if any.
    public func identify(_ image: BINImage) -> ROMIdentifier.Match? {
        identifier.identify(image)
    }

    public func package(id: String) -> DefinitionPackage? {
        packages.first { $0.id == id }
    }
}
