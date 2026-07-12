import XCTest
@testable import AtlasTuneCore

final class MapNameTranslatorTests: XCTestCase {
    private let translator = MapNameTranslator()

    func testTranslatesCommonTuningVocabulary() {
        XCTAssertTrue(translator.translate("Zündwinkel").lowercased().contains("ignition angle"))
        XCTAssertTrue(translator.translate("Solldrehzahl").lowercased().contains("target"))
        XCTAssertTrue(translator.translate("Drehmoment Begrenzung").lowercased().contains("torque"))
        XCTAssertTrue(translator.translate("Klopfgrenze").lowercased().contains("knock"))
    }

    func testCompoundResolvesToLongestMatchFirst() {
        // Leerlaufsolldrehzahl = idle target speed — the whole compound, not "idle" + "target" +
        // "engine speed" fragments colliding.
        let out = translator.translate("Leerlaufsolldrehzahl").lowercased()
        XCTAssertTrue(out.contains("idle target speed"), out)
    }

    func testEnglishNamePassesThroughUnchanged() {
        let english = "Oil pressure target adder factor"
        XCTAssertEqual(translator.translate(english), english)
    }

    func testIdempotent() {
        let once = translator.translate("Kennfeld Zündwinkel")
        XCTAssertEqual(translator.translate(once), once)
    }

    func testLooksGermanDetection() {
        XCTAssertTrue(translator.looksGerman("Füllungsreduktionsfaktor"))
        XCTAssertTrue(translator.looksGerman("Zündwinkel Kennfeld"))
        XCTAssertFalse(translator.looksGerman("Base Timing Map"))
    }

    func testTranslatesRealPackageNamesReducingGerman() throws {
        let package = try XCTUnwrap(DefinitionPackage.bundled(named: "s58_mg1cs049"))
        let germanBefore = package.tables.filter { translator.looksGerman($0.name) }.count
        let germanAfter = package.tables.filter { translator.looksGerman(translator.translate($0.name)) }.count
        XCTAssertLessThan(germanAfter, germanBefore, "Translation should reduce German-looking names")
        // It should meaningfully cut them, not shave one or two.
        XCTAssertLessThan(germanAfter, germanBefore / 2)
    }
}

final class MapExplainerTests: XCTestCase {
    private func def(name: String, category: CalibrationCategory) -> TableDefinition {
        TableDefinition(id: "t", name: name, category: category, subcategory: nil,
                        address: 0, dataType: .uint16, scaling: .identity, unit: "",
                        rows: 1, columns: 1, xAxis: nil, yAxis: nil, valueRange: nil)
    }

    func testNameSpecificExplanationWins() {
        let e = MapExplainer().builtinExplanation(for: def(name: "Wastegate Duty", category: .boost))
        XCTAssertTrue(e.summary.lowercased().contains("wastegate"))
        XCTAssertNotNil(e.tuningNote)
        XCTAssertEqual(e.source, .builtin)
    }

    func testCategoryFallbackWhenNameIsGeneric() {
        let e = MapExplainer().builtinExplanation(for: def(name: "Table 42", category: .fuel))
        XCTAssertTrue(e.summary.lowercased().contains("fuel"))
    }

    func testAsyncPrefersWebProviderThenFallsBack() async {
        struct StubWeb: WebExplanationProvider {
            func explanation(for definition: TableDefinition) async -> MapExplanation? {
                MapExplanation(summary: "From the web", source: .web)
            }
        }
        let withWeb = MapExplainer(web: StubWeb())
        let e = await withWeb.explanation(for: def(name: "Anything", category: .ignition))
        XCTAssertEqual(e.source, .web)

        let offline = MapExplainer()
        let f = await offline.explanation(for: def(name: "Anything", category: .ignition))
        XCTAssertEqual(f.source, .builtin)
    }
}
