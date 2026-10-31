// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The only SMC writes Battery Care makes: pause or allow charging, run on
/// battery while plugged in, the firmware's charge ceiling and the MagSafe
/// light. It finds which of the known keys this Mac has, and writes only a
/// fixed value of the key's own size, and only when it differs.
final class BatteryCareHardware {
    /// A key and the bytes that switch it on and off.
    private struct Switch {
        let key: SMCClient.Key
        let on: [UInt8]
        let off: [UInt8]
    }

    private let client: SMCClient
    /// Bytes that pause charging; the off bytes allow it.
    private let chargeInhibit: [Switch]
    /// Bytes that cut the charger off so the battery runs the Mac.
    private let adapterOff: Switch?
    private let firmwareLimit: SMCClient.Key?
    private let led: SMCClient.Key?

    init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client
        func one(_ name: String, on: [UInt8], off: [UInt8]) -> Switch? {
            guard let key = client.key(named: name), Int(key.dataSize) == on.count else { return nil }
            return Switch(key: key, on: on, off: off)
        }
        // Apple silicon on newer firmware has CHTE; Intel and older firmware CH0B and CH0C.
        if let tahoe = one("CHTE", on: [1, 0, 0, 0], off: [0, 0, 0, 0]) {
            chargeInhibit = [tahoe]
        } else {
            chargeInhibit = [one("CH0B", on: [2], off: [0]), one("CH0C", on: [2], off: [0])].compactMap { $0 }
        }
        adapterOff = one("CHIE", on: [8], off: [0]) ?? one("CH0J", on: [1], off: [0])
            ?? one("CH0I", on: [1], off: [0])
        firmwareLimit = client.key(named: "BCLM").flatMap { $0.dataSize == 1 ? $0 : nil }
        led = client.key(named: "ACLC").flatMap { $0.dataSize == 1 ? $0 : nil }
    }

    var capabilities: BatteryCareCapabilities {
        BatteryCareCapabilities(canPauseCharging: !chargeInhibit.isEmpty,
                                canDischarge: adapterOff != nil,
                                hasFirmwareLimit: firmwareLimit != nil,
                                hasMagSafeLED: led != nil)
    }

    /// Whether the Mac is set to charge, as the keys read now.
    var chargingAllowed: Bool? {
        guard let first = chargeInhibit.first, let bytes = client.readBytes(first.key) else { return nil }
        return bytes != first.on
    }

    @discardableResult
    func setCharging(allowed: Bool) -> Bool {
        chargeInhibit.allSatisfy { write(allowed ? $0.off : $0.on, to: $0.key) }
    }

    @discardableResult
    func setAdapter(enabled: Bool) -> Bool {
        guard let adapterOff else { return enabled }
        return write(enabled ? adapterOff.off : adapterOff.on, to: adapterOff.key)
    }

    @discardableResult
    func setFirmwareLimit(_ percent: Int) -> Bool {
        guard let firmwareLimit else { return true }
        return write([UInt8(min(max(percent, 20), 100))], to: firmwareLimit)
    }

    @discardableResult
    func setLED(_ color: BatteryLEDColor) -> Bool {
        guard let led else { return true }
        let value: UInt8
        switch color {
        case .system: value = 0
        case .off: value = 1
        case .green: value = 3
        case .orange: value = 4
        }
        return write([value], to: led)
    }

    /// Back to the Mac's own charging: what the helper leaves behind when it
    /// stops or Battery Care is turned off.
    func restoreSystemCharging() {
        setAdapter(enabled: true)
        setCharging(allowed: true)
        setFirmwareLimit(100)
        setLED(.system)
    }

    private func write(_ bytes: [UInt8], to key: SMCClient.Key) -> Bool {
        if client.readBytes(key) == bytes { return true }
        do {
            try client.writeBytes(bytes, to: key)
            return true
        } catch {
            return false
        }
    }
}
