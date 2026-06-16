import Foundation

/// Fully describes a single calibration table: where it lives in the BIN, how its bytes
/// decode, and how it is presented to the tuner. Definitions are pure data — there is no
/// hard-coded UI anywhere downstream.
public struct TableDefinition: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var category: CalibrationCategory
    public var subcategory: String?

    /// Byte offset of the first value in the image.
    public var address: Int
    public var dataType: DataType
    public var scaling: Scaling
    public var unit: String

    /// Logical shape. A 1D table has `rows == 1`. Values are laid out row-major.
    public var rows: Int
    public var columns: Int

    /// Column axis (X) for 2D/3D tables. `nil` for a bare 1D scalar list.
    public var xAxis: AxisDefinition?
    /// Row axis (Y) for 3D tables.
    public var yAxis: AxisDefinition?

    /// Inclusive engineering-value range used for validation and edit clamping.
    public var valueRange: ClosedRange<Double>?

    public init(
        id: String,
        name: String,
        description: String = "",
        category: CalibrationCategory,
        subcategory: String? = nil,
        address: Int,
        dataType: DataType,
        scaling: Scaling,
        unit: String,
        rows: Int,
        columns: Int,
        xAxis: AxisDefinition? = nil,
        yAxis: AxisDefinition? = nil,
        valueRange: ClosedRange<Double>? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.subcategory = subcategory
        self.address = address
        self.dataType = dataType
        self.scaling = scaling
        self.unit = unit
        self.rows = rows
        self.columns = columns
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.valueRange = valueRange
    }

    /// Dimensionality classification used by the renderer to pick a default view.
    public enum Dimensionality: Sendable { case scalar, oneD, twoD, threeD }

    public var dimensionality: Dimensionality {
        let cellCount = rows * columns
        if cellCount <= 1 { return .scalar }
        if rows == 1 || columns == 1 { return .oneD }
        if yAxis == nil { return .twoD }
        return .threeD
    }

    /// Total number of value cells.
    public var cellCount: Int { rows * columns }

    /// Total number of value bytes occupied in the image (excluding axes).
    public var byteSize: Int { cellCount * dataType.byteWidth }

    // MARK: Codable for ClosedRange

    private enum CodingKeys: String, CodingKey {
        case id, name, description, category, subcategory
        case address, dataType, scaling, unit, rows, columns, xAxis, yAxis
        case valueRangeLower, valueRangeUpper
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        category = try c.decode(CalibrationCategory.self, forKey: .category)
        subcategory = try c.decodeIfPresent(String.self, forKey: .subcategory)
        address = try c.decode(Int.self, forKey: .address)
        dataType = try c.decode(DataType.self, forKey: .dataType)
        scaling = try c.decode(Scaling.self, forKey: .scaling)
        unit = try c.decode(String.self, forKey: .unit)
        rows = try c.decode(Int.self, forKey: .rows)
        columns = try c.decode(Int.self, forKey: .columns)
        xAxis = try c.decodeIfPresent(AxisDefinition.self, forKey: .xAxis)
        yAxis = try c.decodeIfPresent(AxisDefinition.self, forKey: .yAxis)
        if let lower = try c.decodeIfPresent(Double.self, forKey: .valueRangeLower),
           let upper = try c.decodeIfPresent(Double.self, forKey: .valueRangeUpper) {
            valueRange = lower...upper
        } else {
            valueRange = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(category, forKey: .category)
        try c.encodeIfPresent(subcategory, forKey: .subcategory)
        try c.encode(address, forKey: .address)
        try c.encode(dataType, forKey: .dataType)
        try c.encode(scaling, forKey: .scaling)
        try c.encode(unit, forKey: .unit)
        try c.encode(rows, forKey: .rows)
        try c.encode(columns, forKey: .columns)
        try c.encodeIfPresent(xAxis, forKey: .xAxis)
        try c.encodeIfPresent(yAxis, forKey: .yAxis)
        try c.encodeIfPresent(valueRange?.lowerBound, forKey: .valueRangeLower)
        try c.encodeIfPresent(valueRange?.upperBound, forKey: .valueRangeUpper)
    }
}
