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
    public static let phase1 = DefinitionCatalog(packages: [S58DefinitionPackage.make()])

    /// Identify an image and return the best-matching package plus identity, if any.
    public func identify(_ image: BINImage) -> ROMIdentifier.Match? {
        identifier.identify(image)
    }

    public func package(id: String) -> DefinitionPackage? {
        packages.first { $0.id == id }
    }
}
