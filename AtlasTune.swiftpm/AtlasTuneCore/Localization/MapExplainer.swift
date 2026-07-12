import Foundation

/// A plain-English explanation of what a map does and how it's used in the tune. Sourced first
/// from a curated offline glossary keyed by category/name so it works with no network; an optional
/// enrichment step can fetch more detail dynamically (see `WebExplanationProvider`).
public struct MapExplanation: Sendable, Equatable {
    public let summary: String
    /// Practical tuning guidance ("raise for more mid-range; watch knock").
    public let tuningNote: String?
    /// Where the text came from, so the UI can label live-fetched content.
    public let source: Source

    public enum Source: String, Sendable { case builtin, web }

    public init(summary: String, tuningNote: String? = nil, source: Source = .builtin) {
        self.summary = summary
        self.tuningNote = tuningNote
        self.source = source
    }
}

/// Anything that can fetch a richer explanation dynamically (implemented in the app layer over
/// the network). Kept as a protocol so the engine stays offline and testable.
public protocol WebExplanationProvider: Sendable {
    func explanation(for definition: TableDefinition) async -> MapExplanation?
}

/// Produces a `MapExplanation` for a table. Offline by default; if a `WebExplanationProvider` is
/// supplied it is tried first and the built-in text is the fallback, so the user always sees
/// *something* useful even with no connection.
public struct MapExplainer: Sendable {
    private let web: WebExplanationProvider?

    public init(web: WebExplanationProvider? = nil) {
        self.web = web
    }

    /// Immediate, offline explanation — always available.
    public func builtinExplanation(for definition: TableDefinition) -> MapExplanation {
        let name = definition.name.lowercased()

        // Name-specific hints take priority over the category default.
        if name.contains("wastegate") {
            return MapExplanation(
                summary: "Commands wastegate position/duty, controlling how much boost the turbo builds.",
                tuningNote: "Higher duty = more boost. Change gradually and watch actual-vs-target boost and knock.")
        }
        if name.contains("lambda") {
            return MapExplanation(
                summary: "Target air/fuel ratio (as lambda). Lower is richer, higher is leaner.",
                tuningNote: "Richer (lower λ) is safer under load; leaner recovers economy. Small steps.")
        }
        if name.contains("knock") || name.contains("klopf") {
            return MapExplanation(
                summary: "Knock-control limit or threshold used by the DME's anti-knock logic.",
                tuningNote: "Loosening knock limits is risky — verify fuel quality first.")
        }
        if name.contains("timing") || name.contains("ignition") || name.contains("zünd") {
            return MapExplanation(
                summary: "Ignition timing (spark advance) in crank degrees before top dead centre.",
                tuningNote: "More advance can add torque but raises knock risk; pull timing where knock appears.")
        }
        if name.contains("torque") || name.contains("moment") {
            return MapExplanation(
                summary: "Part of the torque model / limiter the DME uses to request and cap engine torque.",
                tuningNote: "Torque caps can silently limit power — raise ceilings before expecting more boost to stick.")
        }

        // Category fallback.
        switch definition.category {
        case .boost:
            return MapExplanation(summary: "Boost-control table influencing target/delivered manifold pressure.",
                                  tuningNote: "Coordinate with wastegate and torque limits; verify against logs.")
        case .fuel:
            return MapExplanation(summary: "Fueling table affecting mixture and injection.",
                                  tuningNote: "Keep mixture safe under load; validate with a wideband/logs.")
        case .ignition:
            return MapExplanation(summary: "Ignition table affecting spark advance.",
                                  tuningNote: "Advance for torque, retard for knock safety.")
        case .torque:
            return MapExplanation(summary: "Torque-model or limiter table.",
                                  tuningNote: "Limits here can cap everything downstream.")
        case .safety:
            return MapExplanation(summary: "A limit or protection table.",
                                  tuningNote: "Change conservatively — these guard the engine.")
        case .other:
            return MapExplanation(summary: "A calibration table in this ROM.",
                                  tuningNote: "Check the units and safe range before editing.")
        }
    }

    /// Best explanation available: live web enrichment if a provider is set and responds, else the
    /// built-in text. Never throws — falls back silently.
    public func explanation(for definition: TableDefinition) async -> MapExplanation {
        if let web, let fetched = await web.explanation(for: definition) {
            return fetched
        }
        return builtinExplanation(for: definition)
    }
}
