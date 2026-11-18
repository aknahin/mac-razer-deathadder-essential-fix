import Foundation

/// Physical buttons on the DeathAdder Essential, by their firmware id.
public enum MouseButton: UInt8, CaseIterable, Codable {
    case left = 0x01, right = 0x02, middle = 0x03, back = 0x04, forward = 0x05

    public var name: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .middle: "middle"
        case .back: "back"
        case .forward: "forward"
        }
    }

    public init?(name: String) {
        guard let b = Self.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = b
    }
}

/// HID keyboard modifier bits, as used in the keyboard action's modifier byte.
public struct KeyModifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 0x01)
    public static let shift = KeyModifiers(rawValue: 0x02)
    public static let option = KeyModifiers(rawValue: 0x04)
    public static let command = KeyModifiers(rawValue: 0x08)
}

/// What a button does, as stored in the mouse's onboard memory.
///
/// Encoded as `[type, size, params...]`:
/// - `00`            disabled
/// - `01 01 N`       mouse button N (1...5)
/// - `02 02 M K`     keyboard: modifier bits M, HID usage K
public enum ButtonAction: Equatable {
    case disabled
    case mouseButton(UInt8)
    case keyboard(modifiers: KeyModifiers, usage: UInt8)
    case unknown([UInt8])

    public var encoded: [UInt8] {
        switch self {
        case .disabled: [0x00, 0x00]
        case .mouseButton(let n): [0x01, 0x01, n]
        case .keyboard(let m, let k): [0x02, 0x02, m.rawValue, k]
        case .unknown(let raw): raw
        }
    }

    public init(encoded b: ArraySlice<UInt8>) {
        let b = Array(b)
        guard let type = b.first else { self = .unknown(b); return }
        switch type {
        case 0x00: self = .disabled
        case 0x01 where b.count >= 3: self = .mouseButton(b[2])
        case 0x02 where b.count >= 4: self = .keyboard(modifiers: KeyModifiers(rawValue: b[2]), usage: b[3])
        default: self = .unknown(Array(b.prefix(8)))
        }
    }

    /// The factory default for a button.
    public static func factoryDefault(for button: MouseButton) -> ButtonAction {
        .mouseButton(button.rawValue)
    }
}
