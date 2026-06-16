import Foundation

/// Unified Diagnostic Services (UDS, ISO 14229) request/response helpers, used for live logging by
/// repeatedly reading data identifiers. Pure byte logic — testable without a vehicle.
public enum UDS {
    // Service IDs
    public static let readDataByIdentifier: UInt8 = 0x22
    public static let readMemoryByAddress: UInt8 = 0x23
    public static let diagnosticSessionControl: UInt8 = 0x10
    public static let securityAccess: UInt8 = 0x27
    public static let requestUpload: UInt8 = 0x35
    public static let transferData: UInt8 = 0x36
    public static let requestTransferExit: UInt8 = 0x37
    public static let negativeResponse: UInt8 = 0x7F

    /// Sessions
    public static let defaultSession: UInt8 = 0x01
    public static let extendedSession: UInt8 = 0x03

    public static func readDataByIdentifierRequest(_ did: UInt16) -> [UInt8] {
        [readDataByIdentifier, UInt8(did >> 8), UInt8(did & 0xFF)]
    }

    /// ReadMemoryByAddress with a 4-byte address and 1-byte size (addressAndLengthFormatId 0x14).
    /// This is how BMW/Bosch ECUs are live-logged: read the measurement's RAM address directly.
    public static func readMemoryByAddressRequest(address: UInt32, size: UInt8) -> [UInt8] {
        [readMemoryByAddress, 0x14,
         UInt8((address >> 24) & 0xFF), UInt8((address >> 16) & 0xFF),
         UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF),
         size]
    }

    /// ReadMemoryByAddress with a 4-byte address and a variable-width size field. Uses a 1-byte
    /// size (ALFID 0x14) for lengths up to 255, otherwise a 2-byte size (ALFID 0x24) — useful for
    /// reading larger chunks when dumping a ROM.
    public static func readMemoryByAddressRequest(address: UInt32, length: Int) -> [UInt8] {
        let addr: [UInt8] = [UInt8((address >> 24) & 0xFF), UInt8((address >> 16) & 0xFF),
                             UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF)]
        if length <= 0xFF {
            return [readMemoryByAddress, 0x14] + addr + [UInt8(length)]
        }
        return [readMemoryByAddress, 0x24] + addr + [UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)]
    }

    public static func sessionControlRequest(_ session: UInt8) -> [UInt8] {
        [diagnosticSessionControl, session]
    }

    // MARK: Security access (seed/key)

    /// Request a seed for the given security level (odd number, e.g. 0x01, 0x11).
    public static func securityRequestSeed(level: UInt8) -> [UInt8] {
        [securityAccess, level]
    }

    /// Send the computed key for `level` (the send-key sub-function is `level + 1`).
    public static func securitySendKey(level: UInt8, key: [UInt8]) -> [UInt8] {
        [securityAccess, level + 1] + key
    }

    /// Extract the seed bytes from a security-access positive response (0x67, level, seed...).
    public static func securitySeedResponse(_ uds: [UInt8]) -> (level: UInt8, seed: [UInt8])? {
        guard uds.count >= 2, uds[0] == securityAccess + 0x40 else { return nil }
        return (uds[1], Array(uds.dropFirst(2)))
    }

    // MARK: Bulk upload (RequestUpload / TransferData / RequestTransferExit)

    /// RequestUpload for a memory region (4-byte address + 4-byte size, ALFID 0x44, format 0x00).
    public static func requestUploadRequest(address: UInt32, size: UInt32) -> [UInt8] {
        [requestUpload, 0x00, 0x44,
         UInt8((address >> 24) & 0xFF), UInt8((address >> 16) & 0xFF),
         UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF),
         UInt8((size >> 24) & 0xFF), UInt8((size >> 16) & 0xFF),
         UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)]
    }

    /// Parse a RequestUpload positive response to get `maxNumberOfBlockLength` (how many bytes the
    /// ECU returns per TransferData). Response: 0x75, lengthFormatId, maxBlockLength(N bytes).
    public static func requestUploadResponse(_ uds: [UInt8]) -> Int? {
        guard uds.count >= 2, uds[0] == requestUpload + 0x40 else { return nil }
        let lengthBytes = Int(uds[1] >> 4)
        guard uds.count >= 2 + lengthBytes, lengthBytes > 0 else { return nil }
        var value = 0
        for i in 0..<lengthBytes { value = value << 8 | Int(uds[2 + i]) }
        return value
    }

    public static func transferDataRequest(blockSequenceCounter: UInt8) -> [UInt8] {
        [transferData, blockSequenceCounter]
    }

    /// Extract the data block from a TransferData response (0x76, blockSeqCounter, data...).
    public static func transferDataResponse(_ uds: [UInt8]) -> (counter: UInt8, data: [UInt8])? {
        guard uds.count >= 2, uds[0] == transferData + 0x40 else { return nil }
        return (uds[1], Array(uds.dropFirst(2)))
    }

    public static func requestTransferExitRequest() -> [UInt8] { [requestTransferExit] }

    public enum Response: Equatable, Sendable {
        case positive(service: UInt8, data: [UInt8])
        case negative(service: UInt8, code: UInt8)
    }

    public static func parse(_ uds: [UInt8]) -> Response? {
        guard let first = uds.first else { return nil }
        if first == negativeResponse, uds.count >= 3 {
            return .negative(service: uds[1], code: uds[2])
        }
        return .positive(service: first, data: Array(uds.dropFirst()))
    }

    /// For a positive ReadDataByIdentifier response (0x62 DID_hi DID_lo data...), return the DID
    /// and its data bytes.
    public static func readDataResponse(_ uds: [UInt8]) -> (did: UInt16, data: [UInt8])? {
        guard uds.count >= 3, uds[0] == readDataByIdentifier + 0x40 else { return nil }
        let did = UInt16(uds[1]) << 8 | UInt16(uds[2])
        return (did, Array(uds.dropFirst(3)))
    }

    /// For a positive ReadMemoryByAddress response (0x63 followed by the data record), return the
    /// data bytes. The address is not echoed, so callers correlate by request order.
    public static func readMemoryResponse(_ uds: [UInt8]) -> [UInt8]? {
        guard let first = uds.first, first == readMemoryByAddress + 0x40 else { return nil }
        return Array(uds.dropFirst())
    }

    /// 0x78 (responsePending) is sent by the ECU to ask the tester to keep waiting.
    public static func isResponsePending(_ response: Response) -> Bool {
        if case let .negative(_, code) = response { return code == 0x78 }
        return false
    }
}
