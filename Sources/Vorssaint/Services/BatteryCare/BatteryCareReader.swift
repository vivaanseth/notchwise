// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit
import IOKit.ps

/// Reads the battery without any permission, for the app and the helper
/// alike: AppleSmartBattery for the cells and the gauge, the power sources
/// for the percentage macOS shows and its verdict on the battery's health.
enum BatteryCareReader {
    static func read() -> BatteryCareReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let battery = properties?.takeRetainedValue() as? [String: Any],
              battery["BatteryInstalled"] as? Bool != false else { return nil }

        let source = internalPowerSource()
        func int(_ key: String, in dictionary: [String: Any] = battery) -> Int? {
            (dictionary[key] as? NSNumber)?.intValue
        }
        let rawCurrent = int("AppleRawCurrentCapacity")
        let rawMax = int("AppleRawMaxCapacity")
        var hardware: Int?
        if let rawCurrent, let rawMax, rawMax > 0 {
            hardware = min(100, Int((Double(rawCurrent) / Double(rawMax) * 100).rounded()))
        }
        let percent: Int
        if let current = source.flatMap({ int(kIOPSCurrentCapacityKey, in: $0) }),
           let maximum = source.flatMap({ int(kIOPSMaxCapacityKey, in: $0) }), maximum > 0 {
            percent = min(100, Int((Double(current) / Double(maximum) * 100).rounded()))
        } else {
            percent = hardware ?? 0
        }
        let data = battery["BatteryData"] as? [String: Any]
        let cells = (data?["CellVoltage"] as? [NSNumber])?.map(\.intValue) ?? []
        let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        let adapterWatts = (adapter?[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue
        let external = battery["ExternalConnected"] as? Bool ?? false
        func minutes(_ key: String) -> Int? {
            guard let value = int(key), value > 0, value < 65535 else { return nil }
            return value
        }
        let health = source?[kIOPSBatteryHealthKey] as? String
        let condition = source?["BatteryHealthCondition"] as? String ?? ""

        return BatteryCareReading(
            percent: percent,
            hardwarePercent: hardware,
            adapterConnected: external || (adapterWatts ?? 0) > 0,
            isCharging: battery["IsCharging"] as? Bool ?? false,
            fullyCharged: battery["FullyCharged"] as? Bool ?? false,
            temperature: int("Temperature").map { Double($0) / 100 },
            voltage: int("Voltage"),
            cellVoltages: cells,
            amperage: int("Amperage"),
            maxCapacity: rawMax ?? int("NominalChargeCapacity"),
            designCapacity: int("DesignCapacity"),
            cycleCount: int("CycleCount"),
            designCycleCount: int("DesignCycleCount9C"),
            adapterWatts: adapterWatts,
            adapterName: adapter?["Name"] as? String,
            serviceRecommended: health == "Check Battery" || health == "Poor"
                || condition.localizedCaseInsensitiveContains("service"),
            permanentFailure: (int("PermanentFailureStatus") ?? 0) != 0,
            minutesToEmpty: external ? nil : minutes("AvgTimeToEmpty"),
            minutesToFull: minutes("AvgTimeToFull"))
    }

    private static func internalPowerSource() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            return description
        }
        return nil
    }
}
