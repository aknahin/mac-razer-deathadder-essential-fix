import Foundation

/// A Razer HID control packet: a 90-byte feature report.
///
/// Layout (byte offsets):
/// ```
///  0     status            (0x00 on request; 0x02 = OK in response)
///  1     transaction id
///  2-3   remaining packets (always 0 here)
///  4     protocol type     (always 0)
///  5     data size
///  6     command class
///  7     command id
///  8-87  arguments (80 bytes)
///  88    CRC: XOR of bytes 2...87
///  89    reserved
/// ```
public struct RazerPacket: Equatable {
    public static let length = 90

    public enum Status: UInt8 {
        case new = 0x00, busy = 0x01, ok = 0x02, failure = 0x03, timeout = 0x04, notSupported = 0x05
    }

    public var bytes: [UInt8]

    public init(transactionID: UInt8, commandClass: UInt8, commandID: UInt8, dataSize: UInt8, arguments: [UInt8] = []) {
        precondition(arguments.count <= 80, "Razer packets carry at most 80 argument bytes")
        var b = [UInt8](repeating: 0, count: Self.length)
        b[1] = transactionID
        b[5] = dataSize
        b[6] = commandClass
        b[7] = commandID
        for (i, v) in arguments.enumerated() { b[8 + i] = v }
        b[88] = Self.crc(b)
        bytes = b
    }

    public init?(response: [UInt8]) {
        guard response.count >= Self.length else { return nil }
        bytes = Array(response.prefix(Self.length))
    }

    public static func crc(_ b: [UInt8]) -> UInt8 {
        var c: UInt8 = 0
        for i in 2..<88 { c ^= b[i] }
        return c
    }

    public var status: Status? { Status(rawValue: bytes[0]) }
    public var commandClass: UInt8 { bytes[6] }
    public var commandID: UInt8 { bytes[7] }
    public var arguments: ArraySlice<UInt8> { bytes[8..<88] }
}
