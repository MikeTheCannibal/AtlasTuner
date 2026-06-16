import Foundation

public extension DefinitionPackage {
    /// Decode a definition package from JSON data (the format emitted by
    /// `Tools/xdf_to_definition.py`).
    static func decode(from data: Data) throws -> DefinitionPackage {
        try JSONDecoder().decode(DefinitionPackage.self, from: data)
    }

    /// Load a definition package bundled as a JSON resource in the `AtlasTuneCore` module.
    /// Returns `nil` if the resource is missing or fails to decode.
    static func bundled(named name: String) -> DefinitionPackage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decode(from: data)
    }
}
