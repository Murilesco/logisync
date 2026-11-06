import CoreBluetooth
import Foundation

/// iOS/iPadOS port of the Android SyncService.
/// - Watches system-level connection events of the keyboard (registerForConnectionEvents, iOS 13+).
/// - When the keyboard leaves, finds the mouse among the peripherals already connected to the
///   system that expose the Logitech HID++ GATT service, and sends CHANGE_HOST.
/// EXPERIMENTAL: written against the protocol verified on Windows/Android, not yet run on a device.
final class SyncManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let hidppService = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")
    static let hidppChar = CBUUID(string: "00010001-0000-1000-8000-011F2000046D")
    static let hidService = CBUUID(string: "1812")
    static let swId: UInt8 = 0x0B

    @Published var log: [String] = []
    @Published var keyboardName = UserDefaults.standard.string(forKey: "keyboard") ?? "K950" {
        didSet { UserDefaults.standard.set(keyboardName, forKey: "keyboard") }
    }
    @Published var mouseName = UserDefaults.standard.string(forKey: "mouse") ?? "MX Anywhere" {
        didSet { UserDefaults.standard.set(mouseName, forKey: "mouse") }
    }
    @Published var targetChannel = max(1, UserDefaults.standard.integer(forKey: "channel")) {
        didSet { UserDefaults.standard.set(targetChannel, forKey: "channel") }
    }

    private var central: CBCentralManager!
    private var mouse: CBPeripheral?
    private var characteristic: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil,
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "logisync"])
    }

    private func say(_ s: String) {
        let t = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        DispatchQueue.main.async { self.log.insert("\(t)  \(s)", at: 0); self.log = Array(self.log.prefix(100)) }
    }

    private func matches(_ p: CBPeripheral, _ pattern: String) -> Bool {
        (p.name ?? "").localizedCaseInsensitiveContains(pattern)
    }

    // MARK: central

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { say("Bluetooth state \(c.state.rawValue)"); return }
        c.registerForConnectionEvents(options: [.serviceUUIDs: [Self.hidService, Self.hidppService]])
        say("watching connection events")
    }

    func centralManager(_ c: CBCentralManager, willRestoreState dict: [String: Any]) {}

    func centralManager(_ c: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent, for p: CBPeripheral) {
        guard matches(p, keyboardName) else { return }
        let up = event == .peerConnected
        say("keyboard \(up ? "connected" : "disconnected")")
        if !up {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.moveMouse() }
        }
    }

    func moveMouse() {
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.hidppService])
        guard let m = connected.first(where: { matches($0, mouseName) }) else {
            say("mouse not connected to this device"); return
        }
        mouse = m
        m.delegate = self
        central.connect(m)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.discoverServices([Self.hidppService])
    }

    // MARK: peripheral

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.hidppService }) else {
            say("HID++ service not found"); return
        }
        p.discoverCharacteristics([Self.hidppChar], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard let ch = s.characteristics?.first(where: { $0.uuid == Self.hidppChar }) else { return }
        characteristic = ch
        p.setNotifyValue(true, for: ch)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        send(p, feature: 0x00, function: 0, params: [0x18, 0x14]) // root.getFeature(CHANGE_HOST)
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value, v.count >= 3 else { return }
        if v[0] == 0x00 && v[1] == Self.swId {
            let idx = v[2]
            guard idx != 0 else { say("mouse has no CHANGE_HOST"); return }
            send(p, feature: idx, function: 1, params: [UInt8(targetChannel - 1)])
            say("mouse sent to channel \(targetChannel)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.central.cancelPeripheralConnection(p) }
        } else if v[0] == 0xFF {
            say(String(format: "HID++ error 0x%02x", v.count > 3 ? v[3] : 0))
        }
    }

    /// HID++ over GATT: 18 bytes = [feature index, (function << 4) | swId, 16 parameter bytes]
    private func send(_ p: CBPeripheral, feature: UInt8, function: UInt8, params: [UInt8]) {
        guard let ch = characteristic else { return }
        var f = [UInt8](repeating: 0, count: 18)
        f[0] = feature
        f[1] = (function << 4) | Self.swId
        for (i, b) in params.enumerated() { f[2 + i] = b }
        p.writeValue(Data(f), for: ch, type: .withoutResponse)
    }
}
