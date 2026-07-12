import XCTest
@testable import AtlasTuneCore

final class MG1TuningKnowledgeTests: XCTestCase {
    private func definition(name: String, subcategory: String? = nil,
                            category: CalibrationCategory = .other) -> TableDefinition {
        TableDefinition(id: "t", name: name, category: category, subcategory: subcategory,
                        address: 0, dataType: .uint16, scaling: .identity, unit: "",
                        rows: 1, columns: 1, xAxis: nil, yAxis: nil, valueRange: nil)
    }

    func testKeywordMatchesRouteToTheRightSystem() {
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Maximum Torque Limit"))?.id, "mg1.torque")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Maximum Relative Filling Characteristic"))?.id, "mg1.load")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "WGDC P-Gain"))?.id, "mg1.boost")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Boost Setpoint Limitation"))?.id, "mg1.boost")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Lambda Target Bank 1"))?.id, "mg1.fuel")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Base Ignition Timing (Full Load - Warm)"))?.id, "mg1.ignition")
    }

    func testGermanNamesMatchToo() {
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Momentenbegrenzung"))?.id, "mg1.torque")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Zündwinkel Grundkennfeld"))?.id, "mg1.ignition")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Sollfüllung Maximum"))?.id, "mg1.load")
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Ladedruck Begrenzung"))?.id, "mg1.boost")
    }

    func testSubcategoryMatchesWhenNameIsOpaque() {
        let opaque = definition(name: "Kennfeld 47 (autogen)", subcategory: "WGDC breakpoints")
        XCTAssertEqual(MG1TuningKnowledge.article(for: opaque)?.id, "mg1.boost")
    }

    func testCategoryFallbackAndHonestNil() {
        // No keyword hit, but the category still identifies the system.
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Kennfeld 12", category: .fuel))?.id, "mg1.fuel")
        // Nothing recognisable: better no article than a wrong one.
        XCTAssertNil(MG1TuningKnowledge.article(for: definition(name: "Kennfeld 12", category: .other)))
    }

    func testKnockRoutesToIgnitionNotFuel() {
        XCTAssertEqual(MG1TuningKnowledge.article(for: definition(name: "Knock CEL threshold"))?.id, "mg1.ignition")
    }

    func testArticlesAreWellFormed() {
        for article in MG1TuningKnowledge.articles {
            XCTAssertFalse(article.title.isEmpty)
            XCTAssertGreaterThan(article.howItWorks.count, 100, article.id)
            XCTAssertFalse(article.practice.isEmpty, article.id)
            XCTAssertFalse(article.keywords.isEmpty, article.id)
        }
    }

    func testCoverageAcrossRealS58Package() throws {
        // Against all 1370 real tables: the five core categories must resolve to an article, and
        // overall coverage should be high — this is the "does it actually help in the app" check.
        let package = try XCTUnwrap(DefinitionPackage.bundled(named: "s58_mg1cs049"))
        var covered = 0
        for table in package.tables {
            let article = MG1TuningKnowledge.article(for: table)
            if article != nil { covered += 1 }
            if [.boost, .fuel, .ignition, .torque].contains(table.category) {
                XCTAssertNotNil(article, "expected guidance for \(table.category): \(table.name)")
            }
        }
        XCTAssertGreaterThan(Double(covered) / Double(package.tables.count), 0.6,
                             "less than 60% of real tables have guidance (\(covered)/\(package.tables.count))")
    }
}
