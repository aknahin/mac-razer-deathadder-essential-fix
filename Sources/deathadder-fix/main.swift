import AppKit
import Foundation
import RazerKit

let usage = """
deathadder-fix — fix and remap the side buttons of a Razer DeathAdder Essential on macOS

USAGE
  deathadder-fix                 Open the web UI (same as `serve`)
  deathadder-fix serve [--port N] [--no-open]
  deathadder-fix status          Show firmware, mode and every button's assignment
  deathadder-fix fix             Restore the side buttons to Back / Forward
  deathadder-fix set <button> <action>
                                 button: back | forward | middle
                                 action: default | disabled | mouse4 | mouse5 | <shortcut>
                                 shortcut examples: cmd+[   cmd+shift+]   ctrl+up   f11
  deathadder-fix reset           Restore factory defaults on all buttons

Settings are written to the mouse's onboard memory, so they persist across
computers and reboots without any background app.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func withMouse<T>(_ body: (DeathAdderEssential) throws -> T) -> T {
    do { return try body(try DeathAdderEssential.open()) } catch { fail("error: \(error)") }
}

func parseAction(_ text: String, for button: MouseButton) -> ButtonAction? {
    switch text.lowercased() {
    case "default": .factoryDefault(for: button)
    case "disabled", "off", "none": .disabled
    case "mouse4", "back": .mouseButton(4)
    case "mouse5", "forward": .mouseButton(5)
    default: Shortcut.parse(text)
    }
}

func printStatus(_ mouse: DeathAdderEssential) throws {
    print("Razer DeathAdder Essential")
    print("  firmware   \(try mouse.firmwareVersion())")
    let mode = try mouse.deviceMode()
    print("  mode       " + (mode == 0 ? "normal" : String(format: "0x%02x (driver mode)", mode)))
    let actions = try mouse.allActions()
    for b in MouseButton.allCases {
        print("  \(b.name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(Shortcut.describe(actions[b]!))")
    }
}

setvbuf(stdout, nil, _IOLBF, 0)
var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "serve" : args.removeFirst()

switch command {
case "status":
    withMouse { try printStatus($0) }

case "fix":
    withMouse { mouse in
        try mouse.fixSideButtons()
        print("✓ Side buttons restored to Back / Forward.\n")
        try printStatus(mouse)
    }

case "set":
    guard args.count == 2, let button = MouseButton(name: args[0]) else { fail(usage) }
    guard button != .left, button != .right else { fail("Refusing to remap left/right click — you could lock yourself out.") }
    guard let action = parseAction(args[1], for: button) else { fail("Unrecognised action or shortcut: \(args[1])") }
    withMouse { mouse in
        try mouse.setAction(action, for: button)
        print("✓ \(button.name) → \(Shortcut.describe(try mouse.action(for: button)))")
    }

case "reset":
    withMouse { mouse in
        try mouse.resetAll()
        print("✓ All buttons restored to factory defaults.")
    }

case "serve":
    var port: UInt16 = 47_555
    var shouldOpen = true
    while !args.isEmpty {
        let a = args.removeFirst()
        if a == "--port", let p = args.first.flatMap(UInt16.init) { port = p; args.removeFirst() }
        else if a == "--no-open" { shouldOpen = false }
        else { fail(usage) }
    }
    let server = WebServer(port: port)
    do { try server.start() } catch { fail("Could not start the web UI on port \(port): \(error)") }
    let url = URL(string: "http://127.0.0.1:\(port)/?token=\(server.token)")!
    print("DeathAdder Fix is running at \(url.absoluteString)")
    print("Press Ctrl+C to quit.")
    if shouldOpen { NSWorkspace.shared.open(url) }
    // Run as a background (menu-bar-less) app so that opening the .app again
    // while it's running — which macOS delivers as a "reopen" event — brings the UI back.
    let app = NSApplication.shared
    let delegate = AppDelegate(url: url)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()

case "-h", "--help", "help":
    print(usage)

default:
    fail(usage)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let url: URL
    init(url: URL) { self.url = url }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSWorkspace.shared.open(url)
        return false
    }
}
