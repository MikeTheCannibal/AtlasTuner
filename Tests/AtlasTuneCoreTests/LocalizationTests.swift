import XCTest
@testable import AtlasTuneCore

final class LocalizationTests: XCTestCase {
    let glossary = GermanEnglishGlossary.standard

    func testTranslatesCompoundTerms() {
        XCTAssertEqual(glossary.translate("Ladedruck"), "boost pressure")
        XCTAssertEqual(glossary.translate("Bauteilschutz"), "component protection")
        XCTAssertEqual(glossary.translate("Maximalbegrenzung"), "maximum limit")
    }

    func testTranslatesRealLabel() {
        let out = glossary.translate("Kennfeld Beginnwinkel ES1 Warm")
        XCTAssertTrue(out.lowercased().contains("map"), out)
        XCTAssertTrue(out.lowercased().contains("start angle"), out)
        XCTAssertTrue(out.contains("ES1"), "Codes must be preserved: \(out)")
        XCTAssertTrue(out.lowercased().contains("warm"), out)
    }

    func testPreservesEnglishAndCodes() {
        // An already-English label should be left essentially untouched.
        let out = glossary.translate("WGDC D-Factor (FF#2)")
        XCTAssertTrue(out.contains("D-Factor"))
        XCTAssertTrue(out.contains("FF#2"))
    }

    func testMatchesCapitalization() {
        XCTAssertEqual(glossary.translate("Drehzahl"), "Engine speed")
        XCTAssertEqual(glossary.translate("drehzahl"), "engine speed")
    }

    func testLooksGermanHeuristic() {
        XCTAssertTrue(glossary.looksGerman("Maximalbegrenzung I-Anteil Regler"))
        XCTAssertTrue(glossary.looksGerman("Füllungseingriff"))
        XCTAssertFalse(glossary.looksGerman("Timing (Main) (Map 2)"))
    }

    // MARK: Knowledge base

    func testKnowledgeMatchesConcept() {
        let k = CalibrationKnowledge.shared
        let lambda = k.insight(name: "Lambda Targets", subcategory: "Fuel", category: .fuel, unit: "λ")
        XCTAssertTrue(lambda.summary.lowercased().contains("lambda"))

        let boost = k.insight(name: "Boost Targets", subcategory: "Boost", category: .boost, unit: "psi")
        XCTAssertTrue(boost.summary.lowercased().contains("boost"))
    }

    func testKnowledgeMatchesGermanLabel() {
        // Even an untranslated German label should match via its German keywords.
        let k = CalibrationKnowledge.shared
        let i = k.insight(name: "Kennfeld Beginnwinkel ES1 Warm", subcategory: "Ignition",
                          category: .ignition, unit: "°")
        XCTAssertTrue(i.summary.lowercased().contains("ignition"), i.summary)
    }

    func testKnowledgeCategoryFallback() {
        let k = CalibrationKnowledge.shared
        let i = k.insight(name: "Zzz unknown parameter", subcategory: nil, category: .safety, unit: "")
        XCTAssertFalse(i.summary.isEmpty)
        XCTAssertFalse(i.tuningNote.isEmpty)
    }
}
