// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryScheduleAction: Codable, Equatable, Hashable {
    case setLimit(Int)
    case calibrate
    case topUp
    case pauseCharging
    case dischargeTo(Int)
    case lowPowerOn
    case lowPowerOff

    /// The actions the editor offers, with a percentage where one applies.
    static let all: [BatteryScheduleAction] = [
        .setLimit(80), .calibrate, .topUp, .pauseCharging, .dischargeTo(80), .lowPowerOn, .lowPowerOff,
    ]

    var percent: Int? {
        switch self {
        case .setLimit(let value), .dischargeTo(let value): return value
        default: return nil
        }
    }

    func withPercent(_ value: Int) -> BatteryScheduleAction {
        let clamped = min(max(value, BatteryCareSettings.limitRange.lowerBound), BatteryCareSettings.limitRange.upperBound)
        switch self {
        case .setLimit: return .setLimit(clamped)
        case .dischargeTo: return .dischargeTo(clamped)
        default: return self
        }
    }

    /// Two actions of the same kind, whatever their percentage.
    func isSameKind(as other: BatteryScheduleAction) -> Bool {
        switch (self, other) {
        case (.setLimit, .setLimit), (.calibrate, .calibrate), (.topUp, .topUp),
             (.pauseCharging, .pauseCharging), (.dischargeTo, .dischargeTo),
             (.lowPowerOn, .lowPowerOn), (.lowPowerOff, .lowPowerOff):
            return true
        default:
            return false
        }
    }
}

enum BatteryScheduleRepeat: String, Codable, CaseIterable {
    case never, daily, weekdays, weekly, everyTwoWeeks, monthly, yearly
}

struct BatteryScheduleTask: Codable, Equatable, Identifiable {
    var id = UUID()
    var action: BatteryScheduleAction
    var repeats: BatteryScheduleRepeat
    var start: Date
    /// Calendar weekdays (1 is Sunday) for a weekly task; none means the
    /// start date's own weekday.
    var weekdays: Set<Int> = []
    var enabled = true
    var lastRun: Date?
}

struct BatteryScheduleRun: Codable, Equatable, Identifiable {
    var id = UUID()
    var taskID: UUID
    var action: BatteryScheduleAction
    var date: Date
    /// The task ran late, after the Mac slept or was off at its time.
    var caughtUp: Bool
}

/// When scheduled tasks fall due, worked out from the task alone so the app
/// can be closed, asleep or off at the time and still know what it missed.
enum BatteryScheduleSupport {
    /// A task found within this long of its time counts as on time.
    static let onTimeGrace: TimeInterval = 180

    static func monthlyCalibration(now: Date, calendar: Calendar = .current) -> BatteryScheduleTask {
        BatteryScheduleTask(action: .calibrate, repeats: .monthly, start: nextMorning(now: now, calendar: calendar))
    }

    static func biweeklyCalibration(now: Date, calendar: Calendar = .current) -> BatteryScheduleTask {
        BatteryScheduleTask(action: .calibrate, repeats: .everyTwoWeeks, start: nextMorning(now: now, calendar: calendar))
    }

    /// Nine tomorrow morning, where new tasks start.
    static func nextMorning(now: Date, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private static func step(_ repeats: BatteryScheduleRepeat) -> (Calendar.Component, Int)? {
        switch repeats {
        case .daily: return (.day, 1)
        case .everyTwoWeeks: return (.day, 14)
        case .monthly: return (.month, 1)
        case .yearly: return (.year, 1)
        case .never, .weekdays, .weekly: return nil
        }
    }

    private static func days(of task: BatteryScheduleTask, calendar: Calendar) -> Set<Int> {
        switch task.repeats {
        case .weekdays: return [2, 3, 4, 5, 6]
        case .weekly:
            return task.weekdays.isEmpty ? [calendar.component(.weekday, from: task.start)] : task.weekdays
        default: return []
        }
    }

    /// The task's time on `day`, at the start's hour and minute.
    private static func time(of task: BatteryScheduleTask, on day: Date, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: task.start)
        return calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: day)
    }

    /// The task's latest time at or before `now`. Adding whole months to the
    /// start lands on the last day of a shorter month, as AlDente does.
    static func latestOccurrence(of task: BatteryScheduleTask, atOrBefore now: Date,
                                 calendar: Calendar = .current) -> Date? {
        guard task.start <= now else { return nil }
        if task.repeats == .never { return task.start }
        if let (unit, size) = step(task.repeats) {
            let elapsed = calendar.dateComponents([unit], from: task.start, to: now).value(for: unit) ?? 0
            var index = max(0, elapsed / size) + 1
            while index >= 0 {
                if let date = calendar.date(byAdding: unit, value: index * size, to: task.start), date <= now {
                    return date
                }
                index -= 1
            }
            return task.start
        }
        let allowed = days(of: task, calendar: calendar)
        var day = calendar.startOfDay(for: now)
        for _ in 0..<8 {
            if let date = time(of: task, on: day, calendar: calendar), date <= now, date >= task.start,
               allowed.contains(calendar.component(.weekday, from: date)) {
                return date
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return nil
    }

    /// The task's next time after `now`, for showing it.
    static func nextOccurrence(of task: BatteryScheduleTask, after now: Date,
                               calendar: Calendar = .current) -> Date? {
        if task.start > now { return firstOccurrence(of: task, calendar: calendar) }
        if task.repeats == .never { return nil }
        if let (unit, size) = step(task.repeats) {
            let elapsed = calendar.dateComponents([unit], from: task.start, to: now).value(for: unit) ?? 0
            var index = max(0, elapsed / size)
            for _ in 0..<4 {
                if let date = calendar.date(byAdding: unit, value: index * size, to: task.start), date > now {
                    return date
                }
                index += 1
            }
            return nil
        }
        let allowed = days(of: task, calendar: calendar)
        var day = calendar.startOfDay(for: now)
        for _ in 0..<15 {
            if let date = time(of: task, on: day, calendar: calendar), date > now,
               allowed.contains(calendar.component(.weekday, from: date)) {
                return date
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }

    private static func firstOccurrence(of task: BatteryScheduleTask, calendar: Calendar) -> Date? {
        let allowed = days(of: task, calendar: calendar)
        guard !allowed.isEmpty else { return task.start }
        var day = calendar.startOfDay(for: task.start)
        for _ in 0..<8 {
            if let date = time(of: task, on: day, calendar: calendar), date >= task.start,
               allowed.contains(calendar.component(.weekday, from: date)) {
                return date
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return task.start
    }

    /// The time the task should run for now, if it has not run for it yet.
    /// A time missed while the Mac slept or was off runs late only with
    /// catching up on.
    static func dueOccurrence(of task: BatteryScheduleTask, now: Date, catchUp: Bool,
                              calendar: Calendar = .current) -> Date? {
        guard task.enabled, let latest = latestOccurrence(of: task, atOrBefore: now, calendar: calendar) else {
            return nil
        }
        if let lastRun = task.lastRun, lastRun >= latest { return nil }
        if !catchUp, now.timeIntervalSince(latest) > onTimeGrace { return nil }
        return latest
    }
}
