import Foundation
import IOKit.hid

public enum RazerError: Error, CustomStringConvertible {
    case notConnected
    /// macOS refused to open the mouse: the app needs Input Monitoring permission.
    case permissionDenied
    case openFailed(IOReturn)
    case transferFailed(IOReturn)
    case badStatus(RazerPacket.Status?)

    public var description: String {
        switch self {
        case .notConnected: "Razer DeathAdder Essential not found. Is it plugged in?"
        case .permissionDenied: "macOS blocked access to the mouse. Allow DeathAdder Fix in System Settings → Privacy & Security → Input Monitoring."
        case .openFailed(let r): String(format: "Could not open the mouse (IOReturn 0x%08x).", r)
        case .transferFailed(let r): String(format: "USB transfer failed (IOReturn 0x%08x).", r)
        case .badStatus(let s): "Mouse rejected the command (status: \(s.map { "\($0)" } ?? "unknown"))."
        }
    }
}

/// Talks to a Razer DeathAdder Essential over its HID control channel.
///
/// The control channel is a 90-byte feature report on the mouse interface
/// (generic desktop / mouse). Opening that interface for feature reports does
/// not need Input Monitoring permission.
public final class DeathAdderEssential {
    public static let vendorID = 0x1532
    public static let productID = 0x0098
    /// Both onboard profiles; writing both keeps the setting regardless of which one is active.
    public static let profiles: [UInt8] = [0x00, 0x01]

    private let device: IOHIDDevice
    private let transactionID: UInt8 = 0x1f

    private init(device: IOHIDDevice) { self.device = device }

    deinit { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    /// Finds and opens the mouse, or throws `.notConnected`.
    public static func open() throws -> DeathAdderEssential {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
        ] as CFDictionary)
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        guard let device = devices.first(where: {
            (IOHIDDeviceGetProperty($0, kIOHIDMaxFeatureReportSizeKey as CFString) as? Int ?? 0) >= RazerPacket.length
        }) else { throw RazerError.notConnected }
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if r == kIOReturnNotPermitted { throw RazerError.permissionDenied }
        guard r == kIOReturnSuccess else { throw RazerError.openFailed(r) }
        return DeathAdderEssential(device: device)
    }

    public static var isConnected: Bool { (try? open()) != nil }

    /// Whether macOS has granted Input Monitoring, which opening a mouse requires
    /// for an app (a terminal grants it to the tools it runs).
    public static var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt (first time only) and adds the app to the Input Monitoring list.
    @discardableResult
    public static func requestInputMonitoringAccess() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Transport

    /// Sends a command and returns the mouse's reply.
    ///
    /// The control channel is shared state: each command is a "set report" followed by a
    /// "get report", and if another process (a second copy of this app, the CLI) slips its
    /// own command in between, the reply belongs to the wrong request. Two defences:
    /// an inter-process lock held for the whole set→get pair, and a check that the reply
    /// echoes this request's command (and `echo` argument bytes) before it's trusted.
    @discardableResult
    func send(commandClass: UInt8, commandID: UInt8, dataSize: UInt8, arguments: [UInt8] = [],
              echo: Int = 0) throws -> RazerPacket {
        var lastError: Error = RazerError.badStatus(.timeout)
        for attempt in 0..<3 {
            if attempt > 0 { usleep(150_000) }
            do {
                let reply = try Self.withControlLock {
                    try transfer(commandClass: commandClass, commandID: commandID, dataSize: dataSize, arguments: arguments)
                }
                guard reply.commandClass == commandClass, reply.commandID == commandID,
                      Array(reply.arguments.prefix(echo)) == Array(arguments.prefix(echo)) else {
                    lastError = RazerError.badStatus(nil)   // a reply to someone else's request
                    continue
                }
                return reply
            } catch RazerError.badStatus(.notSupported) {
                throw RazerError.badStatus(.notSupported)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Holds an exclusive advisory lock shared by every process using RazerKit.
    private static func withControlLock<T>(_ body: () throws -> T) throws -> T {
        let fd = lockFD
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN) } }
        return try body()
    }

    private static let lockFD: Int32 = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeathAdder Fix", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return Darwin.open(dir.appendingPathComponent("usb.lock").path, O_CREAT | O_RDWR, 0o600)
    }()

    private func transfer(commandClass: UInt8, commandID: UInt8, dataSize: UInt8, arguments: [UInt8]) throws -> RazerPacket {
        let request = RazerPacket(transactionID: transactionID, commandClass: commandClass,
                                  commandID: commandID, dataSize: dataSize, arguments: arguments)
        let w = request.bytes.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, RazerPacket.length)
        }
        guard w == kIOReturnSuccess else { throw RazerError.transferFailed(w) }

        // The firmware needs a moment; poll while it reports busy.
        for _ in 0..<10 {
            usleep(60_000)
            var buf = [UInt8](repeating: 0, count: RazerPacket.length)
            var len = CFIndex(RazerPacket.length)
            let g = buf.withUnsafeMutableBufferPointer {
                IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0, $0.baseAddress!, &len)
            }
            guard g == kIOReturnSuccess else { throw RazerError.transferFailed(g) }
            guard let response = RazerPacket(response: buf) else { continue }
            switch response.status {
            case .busy: continue
            case .ok: return response
            default: throw RazerError.badStatus(response.status)
            }
        }
        throw RazerError.badStatus(.timeout)
    }

    // MARK: - Commands

    /// Firmware version as "major.minor".
    public func firmwareVersion() throws -> String {
        let r = try send(commandClass: 0x00, commandID: 0x81, dataSize: 0x02)
        return "\(r.arguments[8]).\(r.arguments[9])"
    }

    /// Device mode: 0x00 is normal; 0x03 is "driver mode" (Synapse-controlled).
    public func deviceMode() throws -> UInt8 {
        try send(commandClass: 0x00, commandID: 0x84, dataSize: 0x02).arguments[8]
    }

    public func action(for button: MouseButton, profile: UInt8 = 0x01) throws -> ButtonAction {
        let r = try send(commandClass: 0x02, commandID: 0x8c, dataSize: 0x0a, arguments: [profile, button.rawValue, 0x00], echo: 2)
        return ButtonAction(encoded: r.arguments[11...])
    }

    /// Writes `action` for `button` into every onboard profile.
    public func setAction(_ action: ButtonAction, for button: MouseButton) throws {
        for profile in Self.profiles {
            try send(commandClass: 0x02, commandID: 0x0c, dataSize: 0x0a,
                     arguments: [profile, button.rawValue, 0x00] + action.encoded)
        }
    }

    /// Restores factory defaults on the two side buttons (the actual fix).
    public func fixSideButtons() throws {
        try setAction(.factoryDefault(for: .back), for: .back)
        try setAction(.factoryDefault(for: .forward), for: .forward)
    }

    /// Restores factory defaults on every button.
    public func resetAll() throws {
        for b in MouseButton.allCases { try setAction(.factoryDefault(for: b), for: b) }
    }

    public func allActions() throws -> [MouseButton: ButtonAction] {
        var out = [MouseButton: ButtonAction]()
        for b in MouseButton.allCases { out[b] = try action(for: b) }
        return out
    }
}
