import Foundation

/// Parses and formats key combinations like "cmd+shift+]" into HID usages.
public enum Shortcut {
    /// HID keyboard usage ids (USB HID Usage Tables, page 0x07).
    public static let usages: [String: UInt8] = {
        var t: [String: UInt8] = [:]
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() { t[String(c)] = UInt8(0x04 + i) }
        for (i, c) in "1234567890".enumerated() { t[String(c)] = UInt8(0x1e + i) }
        for i in 1...12 { t["f\(i)"] = UInt8(0x3a + i - 1) }
        let named: [String: UInt8] = [
            "enter": 0x28, "return": 0x28, "esc": 0x29, "escape": 0x29, "backspace": 0x2a,
            "tab": 0x2b, "space": 0x2c, "-": 0x2d, "=": 0x2e, "[": 0x2f, "]": 0x30, "\\": 0x31,
            ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38,
            "home": 0x4a, "pageup": 0x4b, "delete": 0x4c, "end": 0x4d, "pagedown": 0x4e,
            "right": 0x4f, "left": 0x50, "down": 0x51, "up": 0x52,
            "mute": 0x7f, "volumeup": 0x80, "volumedown": 0x81,
        ]
        t.merge(named) { a, _ in a }
        return t
    }()

    static let modifierNames: [String: KeyModifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
    ]

    /// "cmd+[" → `.keyboard(modifiers: .command, usage: 0x2f)`.
    public static func parse(_ text: String) -> ButtonAction? {
        var mods: KeyModifiers = []
        var key: UInt8?
        // A literal "+" key isn't expressible here; use "shift+=" instead.
        for raw in text.lowercased().split(separator: "+", omittingEmptySubsequences: true) {
            let part = raw.trimmingCharacters(in: .whitespaces)
            if let m = modifierNames[part] { mods.insert(m) }
            else if let u = usages[part], key == nil { key = u }
            else { return nil }
        }
        guard let key else { return nil }
        return .keyboard(modifiers: mods, usage: key)
    }

    public static func describe(_ action: ButtonAction) -> String {
        switch action {
        case .disabled: return "Disabled"
        case .mouseButton(let n):
            let names: [UInt8: String] = [1: "Left click", 2: "Right click", 3: "Middle click",
                                          4: "Back (mouse button 4)", 5: "Forward (mouse button 5)"]
            return names[n] ?? "Mouse button \(n)"
        case .keyboard(let m, let u):
            var parts: [String] = []
            if m.contains(.control) { parts.append("⌃") }
            if m.contains(.option) { parts.append("⌥") }
            if m.contains(.shift) { parts.append("⇧") }
            if m.contains(.command) { parts.append("⌘") }
            let name = usages.filter { $0.value == u }.map(\.key).min { $0.count < $1.count } ?? String(format: "0x%02x", u)
            return parts.joined() + name.uppercased()
        case .unknown(let raw):
            return "Custom (" + raw.map { String(format: "%02x", $0) }.joined(separator: " ") + ")"
        }
    }
}
