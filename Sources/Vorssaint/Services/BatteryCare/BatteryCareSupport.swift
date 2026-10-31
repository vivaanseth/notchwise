// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Battery Care's names, shared by the app and its root helper. The helper
/// lives outside the app, so rebuilding or moving the app keeps it working;
/// an administrator installs it once.
enum BatteryCareIdentifiers {
    #if VORSSAINT_DEVELOPMENT
    static let appBundleID = "com.vorssaint.voiceos.dev"
    #else
    static let appBundleID = "com.vorssaint.voiceos"
    #endif
    static let helperID = "\(appBundleID).battery"
    static let installedHelper = "/Library/PrivilegedHelperTools/\(helperID)"
    static let launchDaemon = "/Library/LaunchDaemons/\(helperID).plist"
    static let stateDirectory = "/Library/Application Support/\(helperID)"
    /// Raised whenever the helper learns something new, so the app offers
    /// to install the newer one.
    static let helperVersion = 1
}

enum BatteryLowPowerPreference: String, Codable, CaseIterable {
    case unchanged, alwaysOff, alwaysOn, onBattery, onAdapter
}

enum BatteryLEDColor: String, Codable, CaseIterable {
    case system, green, orange, off
}

/// Everything the person chooses. Decoding fills anything missing with its
/// default, so an older app and a newer helper (or the reverse) still agree.
struct BatteryCareSettings: Codable, Equatable {
    static let limitRange = 20...100
    static let sailingWidthRange = 1...20
    static let temperatureRange = 25.0...50.0

    var enabled = true
    var limit = 80
    var sailing = false
    var sailingWidth = 5
    var heatProtection = false
    var maxTemperature = 35.0
    var automaticDischarge = false
    var stopChargingWhenSleeping = false
    var disableSleepUntilLimit = false
    var lowPowerMode = BatteryLowPowerPreference.unchanged
    var magSafeLED = false
    /// Charges to full once when the cells hold far less than the battery
    /// reports, so a limit never keeps an empty battery from charging.
    var fixReadings = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BatteryCareSettings()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? d.limit
        sailing = try c.decodeIfPresent(Bool.self, forKey: .sailing) ?? d.sailing
        sailingWidth = try c.decodeIfPresent(Int.self, forKey: .sailingWidth) ?? d.sailingWidth
        heatProtection = try c.decodeIfPresent(Bool.self, forKey: .heatProtection) ?? d.heatProtection
        maxTemperature = try c.decodeIfPresent(Double.self, forKey: .maxTemperature) ?? d.maxTemperature
        automaticDischarge = try c.decodeIfPresent(Bool.self, forKey: .automaticDischarge) ?? d.automaticDischarge
        stopChargingWhenSleeping = try c.decodeIfPresent(Bool.self, forKey: .stopChargingWhenSleeping)
            ?? d.stopChargingWhenSleeping
        disableSleepUntilLimit = try c.decodeIfPresent(Bool.self, forKey: .disableSleepUntilLimit)
            ?? d.disableSleepUntilLimit
        // A choice a newer app added reads as leaving Low Power Mode alone.
        let lowPower = try? c.decodeIfPresent(BatteryLowPowerPreference.self, forKey: .lowPowerMode)
        lowPowerMode = lowPower ?? d.lowPowerMode
        magSafeLED = try c.decodeIfPresent(Bool.self, forKey: .magSafeLED) ?? d.magSafeLED
        fixReadings = try c.decodeIfPresent(Bool.self, forKey: .fixReadings) ?? d.fixReadings
        self = validated()
    }

    func validated() -> BatteryCareSettings {
        var s = self
        s.limit = min(max(s.limit, Self.limitRange.lowerBound), Self.limitRange.upperBound)
        s.sailingWidth = min(max(s.sailingWidth, Self.sailingWidthRange.lowerBound), Self.sailingWidthRange.upperBound)
        if !s.maxTemperature.isFinite { s.maxTemperature = 35 }
        s.maxTemperature = min(max(s.maxTemperature, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound)
        return s
    }

    /// Where Sailing lets the charge drift down to before charging again.
    var sailingFloor: Int { sailing ? max(limit - sailingWidth, 0) : limit }
}

enum BatteryCalibrationStep: String, Codable {
    case chargeFull, dischargeLow, rechargeFull, returnToLimit
}

/// What the helper is doing beyond holding the limit. It persists, so a
/// calibration carries on across restarts.
enum BatteryCareActivity: Codable, Equatable {
    case none
    case discharge(target: Int)
    case topUp
    case calibration(BatteryCalibrationStep, since: Date)
    /// The battery reported far more than its cells held: charge to full so
    /// its gauge learns again, then return to the limit.
    case readingFix(BatteryCalibrationStep, since: Date)
}

/// One look at the battery, read the same way by the app and the helper.
struct BatteryCareReading: Codable, Equatable {
    /// The percentage macOS shows, which every feature uses, as AlDente does.
    var percent: Int
    /// What the battery's own gauge reports, for information.
    var hardwarePercent: Int?
    /// A charger is attached, even while the helper runs the Mac on battery.
    var adapterConnected: Bool
    var isCharging: Bool
    var fullyCharged: Bool
    var temperature: Double?
    var voltage: Int?
    var cellVoltages: [Int] = []
    /// Milliamps, positive while charging.
    var amperage: Int?
    var maxCapacity: Int?
    var designCapacity: Int?
    var cycleCount: Int?
    var designCycleCount: Int?
    var adapterWatts: Int?
    var adapterName: String?
    var serviceRecommended = false
    var permanentFailure = false
    var minutesToEmpty: Int?
    var minutesToFull: Int?

    var healthPercent: Int? {
        guard let maxCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Int((Double(maxCapacity) / Double(designCapacity) * 100).rounded())
    }

    var averageCellMillivolts: Int? {
        let cells = cellVoltages.filter { $0 > 1000 && $0 < 5000 }
        guard !cells.isEmpty else { return nil }
        return cells.reduce(0, +) / cells.count
    }
}

/// A rough charge from the cells' own voltage. Only good at rest, and only to
/// tell a battery that is nearly empty from one that is not.
enum BatteryChargeEstimate {
    /// Resting voltage of one lithium-ion cell against its charge.
    static let table: [(millivolts: Int, percent: Int)] = [
        (3300, 0), (3450, 2), (3550, 5), (3620, 10), (3680, 20), (3730, 30), (3770, 40),
        (3810, 50), (3860, 60), (3920, 70), (3990, 80), (4070, 90), (4170, 100),
    ]

    static func percent(restingCellMillivolts mv: Int) -> Int {
        guard let first = table.first, let last = table.last else { return 0 }
        if mv <= first.millivolts { return first.percent }
        if mv >= last.millivolts { return last.percent }
        for (low, high) in zip(table, table.dropFirst()) where mv <= high.millivolts {
            let fraction = Double(mv - low.millivolts) / Double(high.millivolts - low.millivolts)
            return low.percent + Int((fraction * Double(high.percent - low.percent)).rounded())
        }
        return last.percent
    }

    /// Next to no current flows, so the voltage is the cells' own.
    static func atRest(_ reading: BatteryCareReading) -> Bool {
        guard let amperage = reading.amperage else { return false }
        return abs(amperage) <= 60
    }

    static func restingPercent(_ reading: BatteryCareReading) -> Int? {
        guard atRest(reading), let cells = reading.averageCellMillivolts else { return nil }
        return percent(restingCellMillivolts: cells)
    }

    /// The battery says it holds plenty while its cells say it is nearly
    /// empty: the gauge lost track, and a limit would keep it from charging.
    static func readingLooksWrong(_ reading: BatteryCareReading) -> Bool {
        guard let cells = restingPercent(reading) else { return false }
        return reading.percent >= 40 && cells <= 15 && reading.percent - cells >= 35
    }
}

enum BatteryCareState: String, Codable {
    case off, charging, paused, sailing, discharging, toppingUp, heatProtection, calibrating,
         fixingReading, onBattery, unplugToContinue, plugInToContinue, sleepPaused
}

enum BatteryCareEvent: String, Codable {
    case limitReached, dischargeFinished, dischargeStoppedLowVoltage, calibrationFinished,
         readingFixStarted, readingFixFinished, heatPaused, weakBattery
}

/// What the helper remembers between looks.
struct BatteryCareMemory: Codable, Equatable {
    var sailingHolds: Bool?
    var heatPausedUntil: Date?
    var readingSuspectSince: Date?
    var lastReadingFix: Date?
    var autoDischargeBlockedUntil: Date?
    var fullSince: Date?
    var lastState: BatteryCareState?
}

/// What this Mac's charging hardware lets the helper do.
struct BatteryCareCapabilities: Codable, Equatable {
    var canPauseCharging = false
    var canDischarge = false
    var hasFirmwareLimit = false
    var hasMagSafeLED = false
}

struct BatteryCareDecision: Equatable {
    var allowCharging: Bool
    var adapterEnabled: Bool
    var preventSleep: Bool
    /// The firmware's own ceiling, where the Mac has one: it holds the
    /// limit while the helper cannot run, as during sleep.
    var firmwareLimit: Int
    var led: BatteryLEDColor
    var state: BatteryCareState
    var activity: BatteryCareActivity
    var events: [BatteryCareEvent]
}

/// The whole charging policy as one pure decision, so it can be tested
/// without a battery and without root.
enum BatteryCarePolicy {
    /// Below this, a cell under load is close to where the Mac shuts down,
    /// so running on battery while plugged in stops at once.
    static let dischargeFloorMillivolts = 3400
    static let heatHold: TimeInterval = 300
    static let readingCheckDelay: TimeInterval = 120
    static let readingFixCooldown: TimeInterval = 12 * 3600
    static let fullChargeTimeout: TimeInterval = 10 * 3600
    static let autoDischargeRetry: TimeInterval = 1800
    static let calibrationLow = 10

    static func decide(settings: BatteryCareSettings, activity: BatteryCareActivity,
                       memory: inout BatteryCareMemory, reading r: BatteryCareReading,
                       capabilities caps: BatteryCareCapabilities, sleeping: Bool,
                       now: Date) -> BatteryCareDecision {
        var events: [BatteryCareEvent] = []
        var decision = evaluate(settings: settings, activity: activity, memory: &memory, reading: r,
                                capabilities: caps, sleeping: sleeping, now: now, events: &events, depth: 0)
        if memory.lastState == .charging, decision.state == .paused, decision.activity == .none,
           r.percent >= settings.limit, settings.limit < 100 {
            events.append(.limitReached)
        }
        if decision.state == .heatProtection, memory.lastState != .heatProtection {
            events.append(.heatPaused)
        }
        memory.lastState = decision.state
        decision.events = events
        decision.led = led(for: decision, settings: settings)
        return decision
    }

    static func dischargeIsSafe(_ r: BatteryCareReading) -> Bool {
        if r.permanentFailure { return false }
        if let lowest = r.cellVoltages.filter({ $0 > 1000 && $0 < 5000 }).min() {
            return lowest >= dischargeFloorMillivolts
        }
        return r.percent > 5
    }

    /// The battery is full: it says so, or it sits at 100% drawing nothing
    /// for five minutes, for batteries that never raise the flag.
    static func isFull(_ r: BatteryCareReading, memory: inout BatteryCareMemory, now: Date) -> Bool {
        if r.fullyCharged { memory.fullSince = nil; return true }
        if r.percent >= 100, r.adapterConnected, let amperage = r.amperage, amperage < 50 {
            let since = memory.fullSince ?? now
            memory.fullSince = since
            return now.timeIntervalSince(since) >= 300
        }
        memory.fullSince = nil
        return false
    }

    private static func evaluate(settings: BatteryCareSettings, activity: BatteryCareActivity,
                                 memory: inout BatteryCareMemory, reading r: BatteryCareReading,
                                 capabilities caps: BatteryCareCapabilities, sleeping: Bool,
                                 now: Date, events: inout [BatteryCareEvent], depth: Int) -> BatteryCareDecision {
        func make(allow: Bool, adapter: Bool = true, preventSleep: Bool = false, ceiling: Int = 100,
                  state: BatteryCareState, activity: BatteryCareActivity) -> BatteryCareDecision {
            BatteryCareDecision(allowCharging: allow, adapterEnabled: adapter, preventSleep: preventSleep,
                                firmwareLimit: ceiling, led: .system, state: state, activity: activity,
                                events: [])
        }
        func again(_ next: BatteryCareActivity) -> BatteryCareDecision {
            guard depth < 4 else { return make(allow: true, state: .charging, activity: next) }
            return evaluate(settings: settings, activity: next, memory: &memory, reading: r,
                            capabilities: caps, sleeping: sleeping, now: now, events: &events, depth: depth + 1)
        }

        guard settings.enabled else {
            memory = BatteryCareMemory(lastReadingFix: memory.lastReadingFix)
            return make(allow: true, state: .off, activity: .none)
        }
        let p = r.percent
        let full = isFull(r, memory: &memory, now: now)
        let safe = dischargeIsSafe(r)
        let plugged = r.adapterConnected
        // A discharge the hardware runs only while a charger is attached;
        // without one, the battery runs the Mac anyway.
        func discharging(_ state: BatteryCareState, _ activity: BatteryCareActivity) -> BatteryCareDecision? {
            guard plugged else { return make(allow: false, state: state, activity: activity) }
            guard caps.canDischarge else { return make(allow: false, state: .unplugToContinue, activity: activity) }
            guard safe else { return nil }
            return make(allow: false, adapter: false, state: state, activity: activity)
        }

        if activity == .none, settings.fixReadings, plugged, depth == 0 {
            if BatteryChargeEstimate.readingLooksWrong(r) {
                let since = memory.readingSuspectSince ?? now
                memory.readingSuspectSince = since
                let rested = memory.lastReadingFix.map { now.timeIntervalSince($0) >= readingFixCooldown } ?? true
                if now.timeIntervalSince(since) >= readingCheckDelay, rested {
                    memory.lastReadingFix = now
                    memory.readingSuspectSince = nil
                    events.append(.readingFixStarted)
                    return again(.readingFix(.chargeFull, since: now))
                }
            } else {
                memory.readingSuspectSince = nil
            }
        }

        switch activity {
        case .topUp:
            return make(allow: true, preventSleep: settings.disableSleepUntilLimit && plugged && !full,
                        state: full ? .paused : (plugged ? .toppingUp : .onBattery), activity: activity)

        case .discharge(let target):
            if p <= target {
                events.append(.dischargeFinished)
                return again(.none)
            }
            if let decision = discharging(plugged ? .discharging : .onBattery, activity) { return decision }
            events.append(.dischargeStoppedLowVoltage)
            if p >= 30 { events.append(.weakBattery) }
            return again(.none)

        case .calibration(let step, let since), .readingFix(let step, let since):
            let calibrating: Bool
            if case .calibration = activity { calibrating = true } else { calibrating = false }
            let label: BatteryCareState = calibrating ? .calibrating : .fixingReading
            func next(_ step: BatteryCalibrationStep) -> BatteryCareActivity {
                calibrating ? .calibration(step, since: now) : .readingFix(step, since: now)
            }
            func finish() -> BatteryCareDecision {
                events.append(calibrating ? .calibrationFinished : .readingFixFinished)
                return again(.none)
            }
            switch step {
            case .chargeFull, .rechargeFull:
                if full || now.timeIntervalSince(since) >= fullChargeTimeout {
                    return again(step == .chargeFull && calibrating ? next(.dischargeLow) : next(.returnToLimit))
                }
                // Charging carries on through sleep, so the Mac may sleep.
                return make(allow: true, state: plugged ? label : .plugInToContinue, activity: activity)
            case .dischargeLow:
                if p <= calibrationLow { return again(next(.rechargeFull)) }
                if let decision = discharging(label, activity) {
                    return BatteryCareDecision(allowCharging: decision.allowCharging,
                                               adapterEnabled: decision.adapterEnabled,
                                               preventSleep: plugged && caps.canDischarge,
                                               firmwareLimit: 100, led: .system, state: decision.state,
                                               activity: activity, events: [])
                }
                if p >= 30 { events.append(.weakBattery) }
                return again(next(.rechargeFull))
            case .returnToLimit:
                if p <= settings.limit || settings.limit >= 100 { return finish() }
                // Without a way to run on battery while plugged in, the
                // limit takes over from here and use brings the charge down.
                if plugged, !caps.canDischarge { return finish() }
                if let decision = discharging(label, activity) { return decision }
                if p >= 50 { events.append(.weakBattery) }
                return finish()
            }

        case .none:
            break
        }

        // Holding the limit.
        let limit = settings.limit
        var wantCharge: Bool
        if limit >= 100 {
            wantCharge = true
            memory.sailingHolds = nil
        } else if settings.sailing {
            var holds = memory.sailingHolds ?? (p > settings.sailingFloor)
            if p >= limit { holds = true }
            if p <= settings.sailingFloor { holds = false }
            memory.sailingHolds = holds
            wantCharge = !holds && p < limit
        } else {
            memory.sailingHolds = nil
            wantCharge = p < limit
        }

        var heatBlocks = false
        if settings.heatProtection, let temperature = r.temperature {
            if temperature >= settings.maxTemperature,
               memory.heatPausedUntil.map({ now >= $0 }) ?? true {
                memory.heatPausedUntil = now.addingTimeInterval(heatHold)
            }
            heatBlocks = memory.heatPausedUntil.map { now < $0 } ?? false
        } else {
            memory.heatPausedUntil = nil
        }
        let ceiling = limit >= 100 ? 100 : limit

        if settings.automaticDischarge, caps.canDischarge, plugged, limit < 100, p > limit {
            let allowed = memory.autoDischargeBlockedUntil.map { now >= $0 } ?? true
            if allowed, safe {
                return make(allow: false, adapter: false, ceiling: ceiling, state: .discharging, activity: .none)
            }
            if allowed, !safe {
                memory.autoDischargeBlockedUntil = now.addingTimeInterval(autoDischargeRetry)
                if memory.lastState == .discharging {
                    events.append(.dischargeStoppedLowVoltage)
                    if p >= 30 { events.append(.weakBattery) }
                }
            }
        }

        let allow = wantCharge && !heatBlocks && !(sleeping && settings.stopChargingWhenSleeping)
        let state: BatteryCareState
        if !plugged {
            state = .onBattery
        } else if wantCharge, heatBlocks {
            state = .heatProtection
        } else if wantCharge, sleeping, settings.stopChargingWhenSleeping {
            state = .sleepPaused
        } else if wantCharge {
            state = limit >= 100 && (full || !r.isCharging && p >= 100) ? .paused : .charging
        } else if settings.sailing, p < limit {
            state = .sailing
        } else {
            state = .paused
        }
        let keepAwake = settings.disableSleepUntilLimit && plugged && allow && limit < 100
        return make(allow: allow, preventSleep: keepAwake, ceiling: ceiling, state: state, activity: .none)
    }

    /// AlDente's MagSafe colors: green at the limit, orange on the way to it.
    private static func led(for decision: BatteryCareDecision, settings: BatteryCareSettings) -> BatteryLEDColor {
        guard settings.enabled, settings.magSafeLED else { return .system }
        switch decision.state {
        case .paused, .sailing: return .green
        case .charging, .discharging, .toppingUp, .heatProtection, .calibrating, .fixingReading,
             .sleepPaused, .unplugToContinue:
            return .orange
        case .off, .onBattery, .plugInToContinue: return .system
        }
    }
}

// MARK: - Talking to the helper

@objc protocol BatteryCareXPCProtocol {
    func status(withReply reply: @escaping (Data) -> Void)
    func perform(_ command: Data, withReply reply: @escaping (Data) -> Void)
}

enum BatteryCareCommand: Codable, Equatable {
    case apply(BatteryCareSettings)
    case discharge(target: Int)
    case stop
    case topUp(Bool)
    case calibrate
    case fixReading
    case led(BatteryLEDColor)
    case lowPowerMode(Bool)
}

struct BatteryCareStatusEvent: Codable, Equatable {
    var serial: Int
    var event: BatteryCareEvent
    var date: Date
    var percent: Int
}

struct BatteryCareStatus: Codable, Equatable {
    var helperVersion: Int
    var settings: BatteryCareSettings
    var activity: BatteryCareActivity
    var state: BatteryCareState
    var reading: BatteryCareReading?
    var capabilities: BatteryCareCapabilities
    var chargingAllowed: Bool
    var adapterEnabled: Bool
    var preventingSleep: Bool
    var events: [BatteryCareStatusEvent]
    var error: String?
}

enum BatteryCareIPC {
    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}
