// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Battery Care's decisions against made-up readings: nothing here reads or
/// writes the charging controller.
enum BatteryCareTests {
    static func run(_ suite: TestSuite) {
        policy(suite)
        readings(suite)
        settings(suite)
        schedule(suite)
        installer(suite)
    }

    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func reading(_ percent: Int, cells: Int = 3900, amperage: Int = 0, plugged: Bool = true,
                                temperature: Double = 30, full: Bool = false) -> BatteryCareReading {
        BatteryCareReading(percent: percent, hardwarePercent: percent, adapterConnected: plugged,
                           isCharging: amperage > 0, fullyCharged: full, temperature: temperature,
                           voltage: cells * 3, cellVoltages: [cells, cells, cells], amperage: amperage)
    }

    private static let intel = BatteryCareCapabilities(canPauseCharging: true, canDischarge: false,
                                                       hasFirmwareLimit: true, hasMagSafeLED: false)
    private static let discharging = BatteryCareCapabilities(canPauseCharging: true, canDischarge: true,
                                                             hasFirmwareLimit: false, hasMagSafeLED: true)

    private static func decide(_ settings: BatteryCareSettings, _ memory: inout BatteryCareMemory,
                               _ reading: BatteryCareReading, activity: BatteryCareActivity = .none,
                               caps: BatteryCareCapabilities = intel, sleeping: Bool = false,
                               at offset: TimeInterval = 0) -> BatteryCareDecision {
        BatteryCarePolicy.decide(settings: settings, activity: activity, memory: &memory, reading: reading,
                                 capabilities: caps, sleeping: sleeping, now: start.addingTimeInterval(offset))
    }

    private static func policy(_ suite: TestSuite) {
        var settings = BatteryCareSettings()
        settings.limit = 80
        var memory = BatteryCareMemory()

        var decision = decide(settings, &memory, reading(60, amperage: 1500))
        suite.expect(decision.allowCharging && decision.state == .charging && decision.firmwareLimit == 80,
                     "below the limit the battery charges, with the firmware ceiling at the limit")
        decision = decide(settings, &memory, reading(80))
        suite.expect(!decision.allowCharging && decision.state == .paused && decision.events == [.limitReached],
                     "charging pauses at the limit and says so once")
        decision = decide(settings, &memory, reading(80))
        suite.expect(decision.events.isEmpty, "holding at the limit is not news again")

        decision = decide(settings, &memory, reading(70), sleeping: true)
        suite.expect(decision.allowCharging, "a sleeping Mac keeps charging toward the limit by default")
        settings.stopChargingWhenSleeping = true
        decision = decide(settings, &memory, reading(70), sleeping: true)
        suite.expect(!decision.allowCharging && decision.state == .sleepPaused, "stop charging when sleeping")
        settings.stopChargingWhenSleeping = false

        decision = decide(settings, &memory, reading(70, plugged: false))
        suite.expect(decision.state == .onBattery && decision.allowCharging,
                     "unplugged reads as on battery, set to charge once plugged in below the limit")

        // Sailing
        settings.sailing = true
        settings.sailingWidth = 5
        memory = BatteryCareMemory()
        decision = decide(settings, &memory, reading(78))
        suite.expect(!decision.allowCharging && decision.state == .sailing, "inside the sailing range it waits")
        decision = decide(settings, &memory, reading(75))
        suite.expect(decision.allowCharging, "at the sailing floor it charges again")
        decision = decide(settings, &memory, reading(78))
        suite.expect(decision.allowCharging, "once charging, it goes on to the limit")
        decision = decide(settings, &memory, reading(80))
        suite.expect(!decision.allowCharging, "and holds at the limit")
        settings.sailing = false

        // Heat protection
        settings.heatProtection = true
        settings.maxTemperature = 35
        memory = BatteryCareMemory()
        decision = decide(settings, &memory, reading(50, temperature: 36))
        suite.expect(!decision.allowCharging && decision.state == .heatProtection && decision.events.contains(.heatPaused),
                     "a hot battery pauses charging")
        decision = decide(settings, &memory, reading(50, temperature: 30), at: 120)
        suite.expect(!decision.allowCharging, "the pause lasts five minutes even once it cools")
        decision = decide(settings, &memory, reading(50, temperature: 30), at: 301)
        suite.expect(decision.allowCharging, "after five cool minutes charging resumes")
        settings.heatProtection = false

        // Off
        settings.enabled = false
        decision = decide(settings, &memory, reading(95))
        suite.expect(decision.allowCharging && decision.adapterEnabled && decision.firmwareLimit == 100
                     && decision.state == .off, "off hands charging back to the Mac")
        settings.enabled = true

        // The reading this Mac had: 89% reported, cells nearly empty.
        settings.limit = 50
        memory = BatteryCareMemory()
        let wrong = reading(89, cells: 3390, amperage: -4)
        decision = decide(settings, &memory, wrong)
        suite.expect(!decision.allowCharging, "a suspect reading is watched for two minutes first")
        decision = decide(settings, &memory, wrong, at: 150)
        suite.expect(decision.allowCharging && decision.state == .fixingReading
                     && decision.events == [.readingFixStarted] && decision.firmwareLimit == 100,
                     "a battery that reports far more than its cells hold charges to full")
        var activity = decision.activity
        decision = decide(settings, &memory, reading(100, cells: 4200, amperage: 0, full: true), activity: activity, at: 7200)
        suite.expect(decision.activity == .none && decision.events.contains(.readingFixFinished)
                     && !decision.allowCharging,
                     "once full, a Mac that can't discharge hands back to the limit")
        decision = decide(settings, &memory, wrong, activity: .none, at: 7400)
        suite.expect(!decision.allowCharging, "a fix is not repeated within twelve hours")
        settings.fixReadings = false
        memory = BatteryCareMemory()
        _ = decide(settings, &memory, wrong)
        decision = decide(settings, &memory, wrong, at: 300)
        suite.expect(!decision.allowCharging, "with the fix off, the limit holds whatever the cells say")
        settings.fixReadings = true

        // Discharge, guarded by the cells' voltage.
        settings.limit = 80
        memory = BatteryCareMemory()
        decision = decide(settings, &memory, reading(90, cells: 3950), activity: .discharge(target: 80), caps: discharging)
        suite.expect(!decision.adapterEnabled && decision.state == .discharging, "discharge runs on battery")
        decision = decide(settings, &memory, reading(88, cells: 3350), activity: .discharge(target: 80), caps: discharging)
        suite.expect(decision.adapterEnabled && decision.activity == .none
                     && decision.events.contains(.dischargeStoppedLowVoltage) && decision.events.contains(.weakBattery),
                     "a collapsing cell voltage ends the discharge before the Mac shuts down")
        decision = decide(settings, &memory, reading(80, cells: 3950), activity: .discharge(target: 80), caps: discharging)
        suite.expect(decision.adapterEnabled && decision.events.contains(.dischargeFinished),
                     "discharge ends at its target")
        decision = decide(settings, &memory, reading(90), activity: .discharge(target: 60), caps: intel)
        suite.expect(decision.state == .unplugToContinue && !decision.allowCharging,
                     "a Mac that can't discharge asks to be unplugged")
        settings.automaticDischarge = true
        decision = decide(settings, &memory, reading(90, cells: 3950), caps: discharging)
        suite.expect(!decision.adapterEnabled && decision.state == .discharging, "automatic discharge")
        settings.automaticDischarge = false

        // Calibration
        memory = BatteryCareMemory()
        activity = .calibration(.chargeFull, since: start)
        decision = decide(settings, &memory, reading(90, amperage: 800), activity: activity, caps: discharging)
        suite.expect(decision.allowCharging && decision.state == .calibrating && decision.firmwareLimit == 100,
                     "calibration charges to full first")
        decision = decide(settings, &memory, reading(100, cells: 4200, full: true), activity: activity, caps: discharging, at: 60)
        guard case .calibration(.dischargeLow, _) = decision.activity else {
            suite.expect(false, "a full battery moves calibration on to running down")
            return
        }
        suite.expect(!decision.adapterEnabled && decision.preventSleep, "calibration runs down awake")
        decision = decide(settings, &memory, reading(10, cells: 3600), activity: decision.activity, caps: discharging, at: 9000)
        guard case .calibration(.rechargeFull, _) = decision.activity else {
            suite.expect(false, "at 10% calibration charges again")
            return
        }
        suite.expect(decision.allowCharging, "recharging")
        decision = decide(settings, &memory, reading(80), activity: .calibration(.returnToLimit, since: start), caps: discharging)
        suite.expect(decision.activity == .none && decision.events.contains(.calibrationFinished),
                     "calibration ends at the limit")
    }

    private static func readings(_ suite: TestSuite) {
        suite.expect(BatteryChargeEstimate.percent(restingCellMillivolts: 3390) <= 2,
                     "3.39 V at rest is close to empty")
        suite.expect(BatteryChargeEstimate.percent(restingCellMillivolts: 4170) == 100, "4.17 V is full")
        suite.expect((45...55).contains(BatteryChargeEstimate.percent(restingCellMillivolts: 3810)), "3.81 V is about half")
        suite.expect(BatteryChargeEstimate.readingLooksWrong(reading(89, cells: 3390, amperage: -4)),
                     "89% with empty cells is a wrong reading")
        suite.expect(!BatteryChargeEstimate.readingLooksWrong(reading(89, cells: 4080, amperage: -4)),
                     "89% with full cells is right")
        suite.expect(!BatteryChargeEstimate.readingLooksWrong(reading(89, cells: 3390, amperage: -2000)),
                     "a battery under load is never judged by its voltage")
        suite.expect(!BatteryChargeEstimate.readingLooksWrong(reading(12, cells: 3390, amperage: 0)),
                     "a low battery that says it is low is right")
        let healthy = BatteryCareReading(percent: 50, adapterConnected: true, isCharging: false, fullyCharged: false,
                                         maxCapacity: 3717, designCapacity: 5103)
        suite.expect(healthy.healthPercent == 73, "health is maximum against design capacity")
    }

    private static func settings(_ suite: TestSuite) {
        let partial = Data(#"{"limit": 150, "sailingWidth": 0, "lowPowerMode": "someday", "maxTemperature": 99}"#.utf8)
        let decoded = BatteryCareIPC.decode(BatteryCareSettings.self, from: partial)
        suite.expect(decoded?.limit == 100 && decoded?.sailingWidth == 1 && decoded?.maxTemperature == 50
                     && decoded?.lowPowerMode == .unchanged && decoded?.fixReadings == true && decoded?.enabled == true,
                     "settings from another version fill in defaults and stay in range")
        var sailing = BatteryCareSettings()
        sailing.limit = 80
        sailing.sailing = true
        sailing.sailingWidth = 10
        suite.expect(sailing.sailingFloor == 70, "the sailing floor sits its width below the limit")
        let status = BatteryCareStatus(helperVersion: 1, settings: sailing, activity: .calibration(.dischargeLow, since: start),
                                       state: .calibrating, reading: nil, capabilities: intel, chargingAllowed: false,
                                       adapterEnabled: false, preventingSleep: true, events: [], error: nil)
        suite.expect(BatteryCareIPC.decode(BatteryCareStatus.self, from: BatteryCareIPC.encode(status)) == status,
                     "the helper's status survives the trip to the app")
        let command = BatteryCareCommand.discharge(target: 60)
        suite.expect(BatteryCareIPC.decode(BatteryCareCommand.self, from: BatteryCareIPC.encode(command)) == command,
                     "commands survive the trip to the helper")
    }

    private static func schedule(_ suite: TestSuite) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let monthly = BatteryScheduleTask(action: .calibrate, repeats: .monthly, start: date(2027, 1, 31))
        suite.expect(BatteryScheduleSupport.latestOccurrence(of: monthly, atOrBefore: date(2027, 3, 1),
                                                             calendar: calendar) == date(2027, 2, 28),
                     "a monthly task on the 31st runs on the last day of February")
        suite.expect(BatteryScheduleSupport.nextOccurrence(of: monthly, after: date(2027, 3, 1), calendar: calendar)
                     == date(2027, 3, 31), "and on the 31st again in March")

        var weekly = BatteryScheduleTask(action: .topUp, repeats: .weekly, start: date(2027, 1, 4, 1))
        weekly.weekdays = [2, 6] // Monday and Friday
        suite.expect(BatteryScheduleSupport.latestOccurrence(of: weekly, atOrBefore: date(2027, 1, 13, 12),
                                                             calendar: calendar) == date(2027, 1, 11, 1),
                     "a weekly task's latest time is its last chosen day")
        suite.expect(BatteryScheduleSupport.nextOccurrence(of: weekly, after: date(2027, 1, 13, 12), calendar: calendar)
                     == date(2027, 1, 15, 1), "its next is the coming Friday")

        let weekdays = BatteryScheduleTask(action: .setLimit(80), repeats: .weekdays, start: date(2027, 1, 1, 8))
        suite.expect(BatteryScheduleSupport.latestOccurrence(of: weekdays, atOrBefore: date(2027, 1, 10, 12),
                                                             calendar: calendar) == date(2027, 1, 8, 8),
                     "weekdays skip the weekend")

        var daily = BatteryScheduleTask(action: .pauseCharging, repeats: .daily, start: date(2027, 1, 1, 9))
        suite.expect(BatteryScheduleSupport.dueOccurrence(of: daily, now: date(2027, 1, 5, 9, 1), catchUp: false,
                                                          calendar: calendar) == date(2027, 1, 5, 9),
                     "a task found on time is due")
        suite.expect(BatteryScheduleSupport.dueOccurrence(of: daily, now: date(2027, 1, 5, 11), catchUp: false,
                                                          calendar: calendar) == nil,
                     "a missed time is skipped without catching up")
        suite.expect(BatteryScheduleSupport.dueOccurrence(of: daily, now: date(2027, 1, 5, 11), catchUp: true,
                                                          calendar: calendar) == date(2027, 1, 5, 9),
                     "and run late with it")
        daily.lastRun = date(2027, 1, 5, 9, 1)
        suite.expect(BatteryScheduleSupport.dueOccurrence(of: daily, now: date(2027, 1, 5, 11), catchUp: true,
                                                          calendar: calendar) == nil, "a task runs once per time")
        let once = BatteryScheduleTask(action: .lowPowerOn, repeats: .never, start: date(2027, 1, 5, 9))
        suite.expect(BatteryScheduleSupport.nextOccurrence(of: once, after: date(2027, 1, 6), calendar: calendar) == nil,
                     "a one-off task has nothing after it")
        suite.expect(BatteryScheduleAction.setLimit(80).withPercent(5) == .setLimit(20)
                     && BatteryScheduleAction.calibrate.withPercent(50) == .calibrate,
                     "a task's percentage stays a valid limit")
    }

    private static func installer(_ suite: TestSuite) {
        suite.expect(BatteryCareInstaller.quoted("/Users/a/Applications/Vorssaint + VoiceOS.app/it's")
                     == "'/Users/a/Applications/Vorssaint + VoiceOS.app/it'\\''s'",
                     "paths reach the shell as one word")
        let install = BatteryCareInstaller.installCommand(helper: "/tmp/x y/helper")
        suite.expect(install.contains("/usr/bin/install -o root -g wheel -m 0755 '/tmp/x y/helper' '\(BatteryCareIdentifiers.installedHelper)'")
                     && install.contains("codesign --verify --strict '\(BatteryCareIdentifiers.installedHelper)'")
                     && install.hasSuffix("launchctl bootstrap system '\(BatteryCareIdentifiers.launchDaemon)'"),
                     "the helper is copied out, checked where root owns it, then started")
        suite.expect(BatteryCareInstaller.removeCommand().hasPrefix("/bin/launchctl bootout system/"),
                     "removing stops the helper first, which hands charging back")
    }
}
