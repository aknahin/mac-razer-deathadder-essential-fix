import Testing
@testable import RazerKit

@Test func packetLayoutAndCRC() {
    let p = RazerPacket(transactionID: 0x1f, commandClass: 0x02, commandID: 0x0c, dataSize: 0x0a,
                        arguments: [0x00, 0x04, 0x00, 0x01, 0x01, 0x04])
    #expect(p.bytes.count == 90)
    #expect(p.bytes[1] == 0x1f)
    #expect(Array(p.bytes[5...7]) == [0x0a, 0x02, 0x0c])
    #expect(Array(p.bytes[8...13]) == [0x00, 0x04, 0x00, 0x01, 0x01, 0x04])
    // 0x0a ^ 0x02 ^ 0x0c ^ 0x04 ^ 0x01 ^ 0x01 ^ 0x04 = 0x04
    #expect(p.bytes[88] == 0x04)
}

@Test(arguments: [
    ButtonAction.disabled, .mouseButton(4), .keyboard(modifiers: [.command, .shift], usage: 0x30),
])
func actionEncodingRoundTrip(_ action: ButtonAction) {
    #expect(ButtonAction(encoded: action.encoded[...]) == action)
}

@Test func decodesValuesReadFromRealMouse() {
    #expect(ButtonAction(encoded: [0x00, 0x00, 0x00][...]) == .disabled)
    #expect(ButtonAction(encoded: [0x01, 0x01, 0x04][...]) == .mouseButton(4))
    #expect(ButtonAction(encoded: [0x02, 0x02, 0x08, 0x2f][...]) == .keyboard(modifiers: .command, usage: 0x2f))
}

@Test func shortcutParsing() {
    #expect(Shortcut.parse("cmd+[") == .keyboard(modifiers: .command, usage: 0x2f))
    #expect(Shortcut.parse("Ctrl+Shift+Up") == .keyboard(modifiers: [.control, .shift], usage: 0x52))
    #expect(Shortcut.parse("f11") == .keyboard(modifiers: [], usage: 0x44))
    #expect(Shortcut.parse("cmd") == nil)
    #expect(Shortcut.parse("cmd+a+b") == nil)
    #expect(Shortcut.parse("hyper+x") == nil)
}

@Test func describe() {
    #expect(Shortcut.describe(.keyboard(modifiers: [.command, .shift], usage: 0x30)) == "⇧⌘]")
    #expect(Shortcut.describe(.mouseButton(4)) == "Back (mouse button 4)")
    #expect(Shortcut.describe(.disabled) == "Disabled")
}
