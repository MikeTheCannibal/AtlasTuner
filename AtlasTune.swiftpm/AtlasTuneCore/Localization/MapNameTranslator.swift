import Foundation

/// Translates the German Bosch/BMW calibration vocabulary that appears in XDF-derived map names
/// into English, so the navigator reads naturally. Works offline and deterministically from a
/// curated tuning-domain glossary: phrases first, then longest-match-first word/compound-fragment
/// replacement (German loves compounds — `Leerlaufsolldrehzahl` = idle target speed — so fragments
/// must match inside words). Names that are already English pass through unchanged.
public struct MapNameTranslator: Sendable {
    public init() {}

    /// Translate one map name. Idempotent and safe to call on English input.
    public func translate(_ name: String) -> String {
        var result = name

        // Multi-word phrases and short function words first, matched on **word boundaries** so an
        // article like "der" never fires inside a word (e.g. "adder" must stay "adder").
        for (german, english) in Self.phrases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: german) + "\\b"
            result = result.replacingOccurrences(of: pattern, with: english,
                                                 options: [.regularExpression, .caseInsensitive])
        }

        // Then fragments, longest first, matched inside words to handle compounds.
        for (german, english) in Self.fragments {
            result = result.replacingOccurrences(of: german, with: english, options: [.caseInsensitive])
        }

        // Tidy: collapse doubled spaces introduced by replacements, trim stray separators.
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Whether a name likely contains German (used to decide if a translated variant is worth
    /// showing at all). Heuristic: any glossary fragment or umlaut present.
    public func looksGerman(_ name: String) -> Bool {
        if name.contains(where: { "äöüÄÖÜß".contains($0) }) { return true }
        let lower = name.lowercased()
        return Self.detectors.contains { lower.contains($0) }
    }

    // MARK: Glossary

    /// Phrases (with articles/prepositions) — applied before fragments.
    static let phrases: [(String, String)] = [
        ("für die Begrenzung des", "for limiting the"),
        ("für die Performanceanzeige", "for the performance display"),
        ("Anpassung des Moments", "Torque adaptation"),
        ("bei BS an Fettlaufgrenze", "at component protection rich-running limit"),
        ("an Fettlaufgrenze", "at rich-running limit"),
        ("für die", "for the"),
        ("für", "for"),
        ("bei", "at"),
        ("des", "of the"),
        ("der", "of the"),
        ("und", "and"),
        ("mit", "with"),
    ]

    /// Compound fragments and words, ordered longest-first at build time.
    static let fragments: [(String, String)] = {
        let raw: [(String, String)] = [
            // Compounds seen in the S58 set
            ("leerlaufsolldrehzahl", "idle target speed "),
            ("füllungsreduktionsfaktor", "cylinder-fill reduction factor "),
            ("drehzahlabhängige", "speed-dependent "),
            ("drehzahlabhängig", "speed-dependent "),
            ("ansauglufttemperatur", "intake air temperature "),
            ("sammlertemperaturen", "manifold temperatures "),
            ("sammlertemperatur", "manifold temperature "),
            ("temperaturkorrektur", "temperature correction "),
            ("bauteilschutzlambdas", "component-protection lambda "),
            ("bauteilschutzlambda", "component-protection lambda "),
            ("bauteilschutz", "component protection "),
            ("kraftstoffqualität", "fuel quality "),
            ("einlassventilhub", "intake valve lift "),
            ("füllungseingriff", "cylinder-fill intervention "),
            ("füllungsdeckel", "cylinder-fill cap "),
            ("fettlaufgrenze", "rich-running limit "),
            ("lambdakorrektur", "lambda correction "),
            ("klopfgrenze", "knock limit "),
            ("superklopfen", "super-knock "),
            ("beginnwinkel", "start angle "),
            ("zündwinkel", "ignition angle "),
            ("raildruck", "rail pressure "),
            ("abgasklappe", "exhaust flap "),
            ("ladedruck", "boost pressure "),
            ("wastegatestellung", "wastegate position "),
            ("drehmoment", "torque "),
            ("drehzahl", "engine speed "),
            ("kennfeld", "map "),
            ("kennlinie", "curve "),
            ("füllung", "cylinder fill "),
            ("leerlauf", "idle "),
            ("leistung", "power "),
            ("begrenzung", "limit "),
            ("begrenzt", "limited "),
            ("normierung", "normalisation "),
            ("anpassung", "adaptation "),
            ("korrektur", "correction "),
            ("präventiv", "preventive "),
            ("schwelle", "threshold "),
            ("gefahren", "driven "),
            ("grenzen", "limits "),
            ("grenze", "limit "),
            ("faktor", "factor "),
            ("späten", "late "),
            ("moments", "torque "),
            ("moment", "torque "),
            ("maximaler", "maximum "),
            ("maximale", "maximum "),
            ("minimale", "minimum "),
            ("soll", "target "),
            ("ist", "actual "),
        ]
        // Longest-first so compounds win over their fragments.
        return raw.sorted { $0.0.count > $1.0.count }
    }()

    /// Cheap German detectors for `looksGerman` (subset of distinctive fragments).
    static let detectors: [String] = [
        "zünd", "kraftstoff", "drehzahl", "kennfeld", "kennlinie", "füllung", "begrenzung",
        "drehmoment", "klopf", "leerlauf", "schwelle", "korrektur", "anpassung", "normierung",
        "abgasklappe", "bauteilschutz", "raildruck", " soll", " für ", "faktor ",
    ]
}
