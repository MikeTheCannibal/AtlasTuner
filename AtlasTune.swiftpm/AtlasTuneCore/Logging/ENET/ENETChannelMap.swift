import Foundation

/// One loggable signal: which RAM address to read, how many bytes, and how to scale them. Sourced
/// from the vehicle A2L's MEASUREMENT objects (ECU_ADDRESS + COMPU_METHOD). BMW ECU RAM is
/// little-endian (A2L `BYTE_ORDER MSB_LAST`).
public struct ENETSignal: Sendable {
    public let channel: LogChannel
    public let address: UInt32
    public let dataType: DataType
    public let scaling: Scaling
    public let byteOrder: ByteOrder

    public init(channel: LogChannel, address: UInt32, dataType: DataType,
                scaling: Scaling, byteOrder: ByteOrder = .littleEndian) {
        self.channel = channel
        self.address = address
        self.dataType = dataType
        self.scaling = scaling
        self.byteOrder = byteOrder
    }

    /// Bytes to request for this signal.
    public var size: UInt8 { UInt8(dataType.byteWidth) }
}

/// Maps a set of measurement addresses to channels for a tester/ECU address pair, read live via
/// UDS ReadMemoryByAddress over DoIP.
public struct ENETChannelMap: Sendable {
    /// Tester (client) logical address. 0x0E00 is the common external-tester address.
    public var testerAddress: UInt16
    /// Target ECU (DME) logical address.
    public var ecuAddress: UInt16
    public var signals: [ENETSignal]

    public init(testerAddress: UInt16, ecuAddress: UInt16, signals: [ENETSignal]) {
        self.testerAddress = testerAddress
        self.ecuAddress = ecuAddress
        self.signals = signals
    }

    public var addresses: [UInt32] { signals.map(\.address) }

    public var channels: [LogChannel] {
        var seen = Set<String>()
        return signals.compactMap { seen.insert($0.channel.id).inserted ? $0.channel : nil }
    }
}

/// Turns ReadMemoryByAddress responses (keyed by the requested address) into a `LogSample`.
public struct ENETDecoder: Sendable {
    public let map: ENETChannelMap
    public init(map: ENETChannelMap) { self.map = map }

    public func sample(time: TimeInterval, responses: [UInt32: [UInt8]]) -> LogSample {
        var values: [String: Double] = [:]
        for signal in map.signals {
            guard let bytes = responses[signal.address] else { continue }
            let image = BINImage(bytes: Data(bytes), byteOrder: signal.byteOrder)
            if let raw = try? image.readRaw(signal.dataType, at: 0) {
                values[signal.channel.id] = signal.scaling.display(fromRaw: raw)
            }
        }
        return LogSample(time: time, values: values)
    }
}

public extension LogChannel {
    // Channels beyond the standard set that the S58 A2L exposes.
    static let oilTemp = LogChannel(id: "toil", name: "Oil Temp", unit: "°C")
    static let vehicleSpeed = LogChannel(id: "vspd", name: "Vehicle Speed", unit: "km/h")
    static let gear = LogChannel(id: "gear", name: "Gear", unit: "")
    static let ambientPressure = LogChannel(id: "pamb", name: "Ambient Pressure", unit: "hPa")
    static let boostDeviation = LogChannel(id: "plddiff", name: "Boost Dev (target−actual)", unit: "hPa")
    static let knockIntensity = LogChannel(id: "knkint", name: "Knock Intensity", unit: "")
    static let torqueLimitFactor = LogChannel(id: "tqlim", name: "Torque Limit Factor", unit: "")
}

public extension ENETChannelMap {
    /// S58 / MG1CS049 live-logging map derived from the vehicle A2L's MEASUREMENT objects.
    ///
    /// Addresses, data types and scalings are taken directly from the A2L (scaling = COMPU_METHOD
    /// `f/b`, e.g. relative charge = 3/128 = 0.0234375, matching its `q0p0234` name). All values are
    /// little-endian RAM reads via ReadMemoryByAddress.
    ///
    /// IMPORTANT: the source A2L is software variant `F4C2L8R6B` (EPK 5c64020_135_006), while the
    /// imported BIN is `F4C2L8Y8B` / CB_011. RAM addresses are tied to the software build, so these
    /// must be validated against the actual vehicle/matching A2L before the values can be trusted.
    /// Lambda and absolute boost/manifold pressure are not in this A2L's measurement subset.
    static let s58FromA2L = ENETChannelMap(
        testerAddress: 0x0E00,
        ecuAddress: 0x0010,
        signals: [
            ENETSignal(channel: .rpm, address: 0x500020E6, dataType: .int16,
                       scaling: Scaling(factor: 0.5, offset: 0, decimals: 0)),            // Epm_nEng
            ENETSignal(channel: .load, address: 0x5002493A, dataType: .uint16,
                       scaling: Scaling(factor: 3.0 / 128.0, offset: 0, decimals: 1)),     // AirMod_ratChrgAirCyl
            ENETSignal(channel: .coolant, address: 0x60002688, dataType: .int16,
                       scaling: Scaling(factor: 0.01, offset: 0, decimals: 1)),            // Tmot
            ENETSignal(channel: .iat, address: 0x60024B6E, dataType: .int16,
                       scaling: Scaling(factor: 0.1, offset: 0, decimals: 1)),             // Tans
            ENETSignal(channel: .knock, address: 0x600033A2, dataType: .int16,
                       scaling: Scaling(factor: 0.1, offset: 0, decimals: 1)),             // Dzw_tot_kr (total retard)
            ENETSignal(channel: .oilTemp, address: 0x7000D690, dataType: .int16,
                       scaling: Scaling(factor: 0.1, offset: 0, decimals: 1)),             // Toel_wm
            ENETSignal(channel: .vehicleSpeed, address: 0x6000393E, dataType: .uint16,
                       scaling: Scaling(factor: 1.0, offset: 0, decimals: 0)),             // V
            ENETSignal(channel: .gear, address: 0x5000460A, dataType: .uint8,
                       scaling: Scaling(factor: 1.0, offset: 0, decimals: 0)),             // Gangi
            ENETSignal(channel: .ambientPressure, address: 0x60024B66, dataType: .uint16,
                       scaling: Scaling(factor: 0.125, offset: 0, decimals: 0)),           // Pumg
            ENETSignal(channel: .boostDeviation, address: 0x60002218, dataType: .int16,
                       scaling: Scaling(factor: 0.125, offset: 0, decimals: 0)),           // BMWtchbas_p_Dif_sw (Pld_diff)
            ENETSignal(channel: .knockIntensity, address: 0x50025F00, dataType: .uint8,
                       scaling: Scaling(factor: 16.0 / 256.0, offset: 0, decimals: 2)),    // IKCtl_facKnkInten_u8
            ENETSignal(channel: .torqueLimitFactor, address: 0x6000432A, dataType: .uint8,
                       scaling: Scaling(factor: 1.0 / 256.0, offset: 0, decimals: 3)),     // BMWtqe_fac_EngTqLimd
        ]
    )

    /// Backwards-compatible alias used by existing call sites.
    static var s58Placeholder: ENETChannelMap { s58FromA2L }
}
