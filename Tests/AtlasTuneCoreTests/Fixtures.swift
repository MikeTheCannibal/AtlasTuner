import Foundation
@testable import AtlasTuneCore

/// Synthetic, compact fixtures so tests don't depend on the (large) real S58 package.
enum Fixtures {
    static let imageSize = 64
    static let signatureAddress = 40
    static let signaturePattern: [UInt8] = [0xA5, 0x5A, 0x12]

    static let xAxis = AxisDefinition.fixed(id: "x", name: "RPM", unit: "rpm", values: [1000, 2000, 3000, 4000])
    static let yAxis = AxisDefinition.fixed(id: "y", name: "Load", unit: "%", values: [20, 40, 60])

    /// 3 rows x 4 columns, uint16, scale 0.1, stored at address 0.
    static var table3D: TableDefinition {
        TableDefinition(
            id: "t.map", name: "Test Map", description: "Boost target map", category: .boost,
            subcategory: "Boost Targets", address: 0, dataType: .uint16,
            scaling: Scaling(factor: 0.1, offset: 0, decimals: 1), unit: "psi",
            rows: 3, columns: 4, xAxis: xAxis, yAxis: yAxis, valueRange: 0...30
        )
    }

    /// 1D, 4 columns, uint8, scale 1.0, stored at address 24.
    static var table1D: TableDefinition {
        TableDefinition(
            id: "t.scalar", name: "Scalar List", category: .fuel, subcategory: "Fuel Scalars",
            address: 24, dataType: .uint8, scaling: .identity, unit: "%",
            rows: 1, columns: 4, xAxis: xAxis, yAxis: nil, valueRange: 0...100
        )
    }

    static func package() -> DefinitionPackage {
        DefinitionPackage(
            id: "test.pkg", family: "TestFamily", calibrationVersion: "1.0",
            expectedImageSizes: [imageSize], versionField: nil,
            signatures: [ROMSignature(address: signatureAddress, pattern: signaturePattern, label: "magic")],
            tables: [table3D, table1D]
        )
    }

    /// A blank image of the fixture size with the identification signature written in.
    static func blankImage() -> BINImage {
        var image = BINImage(bytes: Data(repeating: 0, count: imageSize), byteOrder: .littleEndian)
        try! image.writeBytes(signaturePattern, at: signatureAddress)
        return image
    }

    /// An image pre-loaded with a known ramp in the 3D table for read tests.
    static func loadedImage() -> BINImage {
        var image = blankImage()
        let def = table3D
        // Fill the 3x4 map with engineering values 1.0, 2.0, ... 12.0.
        var v = 1.0
        for row in 0..<def.rows {
            for col in 0..<def.columns {
                let offset = def.address + (row * def.columns + col) * def.dataType.byteWidth
                let raw = def.scaling.raw(fromDisplay: v)
                try! image.writeRaw(raw, type: def.dataType, at: offset)
                v += 1.0
            }
        }
        return image
    }
}
