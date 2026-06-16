import Foundation

/// Offline German→English translation tuned for BMW/Bosch ECU calibration labels.
///
/// XDF table names from MHD+ are a mix of English and BMW's internal German (e.g.
/// "Kennlinie Faktor Füllungseingriff bei BS an Fettlaufgrenze"). A live translation service would
/// need network + entitlements; instead this is a deterministic, instant, on-device glossary of
/// the automotive German that actually appears in these labels. It translates known multi-word
/// phrases first, then word-by-word, leaving codes/abbreviations (ES1, KF_…, Rfv) untouched.
public struct GermanEnglishGlossary: Sendable {
    /// Ordered longest-first so multi-word phrases win before their constituent words.
    private let phrases: [(de: String, en: String)]
    /// Single-token lookup, keyed by lowercased German word (incl. common compounds).
    private let terms: [String: String]

    public init(phrases: [(String, String)], terms: [String: String]) {
        self.phrases = phrases.sorted { $0.0.count > $1.0.count }.map { (de: $0.0, en: $0.1) }
        self.terms = terms
    }

    /// Translate `text`, preserving punctuation, numbers and untranslatable codes.
    public func translate(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var working = text
        for phrase in phrases {
            working = working.replacingOccurrences(of: phrase.de, with: phrase.en, options: [.caseInsensitive])
        }

        var result = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            if let english = terms[token.lowercased()] {
                result += Self.matchingCase(english, like: token)
            } else {
                result += token
            }
            token = ""
        }
        for character in working {
            if character.isLetter {
                token.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return Self.tidy(result)
    }

    /// Heuristic: does this label contain German worth translating?
    public func looksGerman(_ text: String) -> Bool {
        if text.contains(where: { "äöüÄÖÜß".contains($0) }) { return true }
        var token = ""
        for character in text + " " {
            if character.isLetter { token.append(character) }
            else {
                if terms[token.lowercased()] != nil { return true }
                token = ""
            }
        }
        return phrases.contains { text.range(of: $0.de, options: [.caseInsensitive]) != nil }
    }

    // MARK: Helpers

    private static func matchingCase(_ english: String, like source: String) -> String {
        guard let first = source.first, first.isUppercase, let target = english.first else { return english }
        return target.uppercased() + english.dropFirst()
    }

    private static func tidy(_ text: String) -> String {
        var s = text
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
