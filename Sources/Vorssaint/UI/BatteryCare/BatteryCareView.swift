// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Battery Care: the charge limit and everything around it, as one page that
/// the island's battery detail and the app panel's both show.
struct BatteryCareView: View {
    @ObservedObject private var service = BatteryCareService.shared
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var monitor = SystemMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.temperatureUnit) private var temperatureUnit = TemperatureUnit.celsius.rawValue
    @AppStorage(DefaultsKey.batteryCareNotifications) private var notifications = true
    @AppStorage(DefaultsKey.batteryCareCatchUp) private var catchUp = false
    @AppStorage(DefaultsKey.batteryCareSleepStopUnplugged) private var sleepEndsUnplugged = false
    @AppStorage(DefaultsKey.batteryLimit) private var keepAwakeBatteryLimit = 10
    @State private var limitDraft: Double?
    @State private var draft: BatteryScheduleTask?
    @State private var copiedCommand: String?

    private var s: BatteryCareFeatureStrings { FeatureStrings.batteryCare(l10n.language) }
    private var reading: BatteryCareReading? { service.reading }
    private var canControl: Bool { service.helperState == .running }
    private var unit: TemperatureUnit { TemperatureUnit(rawValue: temperatureUnit) ?? .celsius }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            card(header)
            if service.otherLimiter != nil || service.helperState != .running || service.message != nil {
                card(helperCard)
            }
            if hasFindings { card(checkCard) }
            card(limitCard)
            card(BatteryPowerFlowView(power: monitor.snapshot.power, strings: s))
            card(optionsCard)
            card(sleepCard)
            card(healthCard)
            card(energyCard)
            card(scheduleCard)
            card(shortcutsCard)
            if service.helperInstalled { card(removeCard) }
        }
        .onAppear { service.viewAppeared() }
        .onDisappear { service.viewDisappeared() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: headerSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .frame(width: 18)
                Text(reading.map { "\($0.percent)%" } ?? "-")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let hardware = reading?.hardwarePercent {
                    Text(String(format: s.hardwareFormat, hardware))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            BatteryLimitBar(percent: reading?.percent ?? 0,
                            limit: Int((limitDraft ?? Double(service.settings.limit)).rounded()),
                            sailingFloor: service.settings.sailing ? service.settings.sailingFloor : nil,
                            color: stateColor)
                .frame(height: 10)
            Text(stateText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var headerSymbol: String {
        switch service.state {
        case .charging, .toppingUp, .fixingReading: return "bolt.fill"
        case .discharging, .onBattery: return "battery.50"
        case .heatProtection: return "thermometer.sun.fill"
        case .calibrating: return "arrow.triangle.2.circlepath"
        case .off: return "battery.100"
        default: return "powerplug.fill"
        }
    }

    /// Calm colors for the usual states; orange only when something waits on the person.
    private var stateColor: Color {
        switch service.state {
        case .charging, .toppingUp, .fixingReading, .calibrating: return .green
        case .paused, .sailing: return .teal
        case .discharging, .onBattery: return .yellow
        case .heatProtection, .unplugToContinue, .plugInToContinue: return .orange
        case .off, .sleepPaused: return .gray
        }
    }

    private var stateText: String {
        let settings = service.settings
        let percent = reading?.percent ?? 0
        switch service.state {
        case .off: return s.stateOff
        case .charging: return String(format: s.stateChargingFormat, settings.limit)
        case .paused:
            if percent >= 100 || settings.limit >= 100 { return s.stateFull }
            if percent > settings.limit + 1 { return String(format: s.statePausedAboveFormat, settings.limit) }
            return String(format: s.stateHoldingFormat, settings.limit)
        case .sailing: return String(format: s.stateSailingFormat, settings.sailingFloor)
        case .discharging:
            if case .discharge(let target) = service.activity {
                return String(format: s.stateDischargingFormat, target)
            }
            return String(format: s.stateDischargingFormat, settings.limit)
        case .toppingUp: return s.stateToppingUp
        case .heatProtection:
            let temperature = reading?.temperature.map { MetricFormat.temperature($0, unit: unit) } ?? "-"
            return String(format: s.stateHeatFormat, temperature)
        case .calibrating, .fixingReading:
            let step: BatteryCalibrationStep
            switch service.activity {
            case .calibration(let current, _), .readingFix(let current, _): step = current
            default: step = .chargeFull
            }
            let name: String
            switch step {
            case .chargeFull: name = s.stepChargeFull
            case .dischargeLow: name = s.stepDischargeLow
            case .rechargeFull: name = s.stepRechargeFull
            case .returnToLimit: name = s.stepReturn
            }
            if service.state == .fixingReading { return String(format: s.stateFixingFormat, name) }
            let index = [BatteryCalibrationStep.chargeFull, .dischargeLow, .rechargeFull, .returnToLimit]
                .firstIndex(of: step).map { $0 + 1 } ?? 1
            return String(format: s.stateCalibratingFormat, index, name)
        case .onBattery: return s.stateOnBattery
        case .unplugToContinue: return s.stateUnplug
        case .plugInToContinue: return s.statePlugIn
        case .sleepPaused: return s.stateSleepPaused
        }
    }

    // MARK: Helper

    private var helperCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let other = service.otherLimiter {
                let name = other.localizedName ?? "AlDente"
                caption(String(format: s.otherLimiterFormat, name), color: .orange)
                Button(String(format: s.quitOtherFormat, name), action: service.quitOtherLimiter)
                    .controlSize(.small)
            }
            switch service.helperState {
            case .running:
                EmptyView()
            case .notInstalled, .outdated:
                caption(service.helperState == .outdated ? s.helperOutdated : s.helperNeeded)
                Button(service.isInstalling ? s.waitingForApproval
                       : service.helperState == .outdated ? s.updateHelper : s.installHelper,
                       action: service.installHelper)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .disabled(service.isInstalling)
            case .unreachable:
                caption(s.helperUnreachable, color: .orange)
                Button(s.installHelper, action: service.installHelper)
                    .controlSize(.small)
                    .disabled(service.isInstalling)
            }
            if let message = service.message { caption(message, color: .red) }
            if let error = service.status?.error { caption(error, color: .red) }
        }
    }

    // MARK: Battery check

    private var readingIsWrong: Bool { reading.map(BatteryChargeEstimate.readingLooksWrong) ?? false }

    private var hasFindings: Bool {
        readingIsWrong || service.state == .fixingReading || reading?.serviceRecommended == true
            || service.weakBattery != nil
    }

    private var checkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(s.checkTitle, systemImage: "stethoscope")
                .font(.system(size: 11.5, weight: .semibold))
            if service.state == .fixingReading {
                caption(s.wrongReadingFixing, color: .green)
            } else if readingIsWrong, let reading, let cells = reading.averageCellMillivolts {
                caption(String(format: s.wrongReadingFormat, reading.percent,
                               String(format: "%.2f", locale: l10n.language.formattingLocale(), Double(cells) / 1000)))
                caption(canControl ? s.wrongReadingFix : s.wrongReadingNoHelper)
                if canControl {
                    Button(s.chargeToFull, action: service.fixReading)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            if let reading, reading.serviceRecommended {
                caption(String(format: s.serviceFormat, reading.healthPercent ?? 0, reading.cycleCount ?? 0),
                        color: .orange)
            }
            if let weak = service.weakBattery {
                caption(String(format: s.weakBatteryFormat,
                               weak.date.formatted(date: .abbreviated, time: .shortened), weak.percent),
                        color: .orange)
            }
        }
    }

    // MARK: Limit and actions

    private var limitCard: some View {
        let settings = service.settings
        let percent = reading?.percent ?? 0
        let shown = Int((limitDraft ?? Double(settings.limit)).rounded())
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.limitTitle).font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Text("\(shown)%").font(.system(size: 11.5, weight: .semibold).monospacedDigit())
            }
            Slider(value: Binding(get: { limitDraft ?? Double(settings.limit) }, set: { limitDraft = $0 }),
                   in: Double(BatteryCareSettings.limitRange.lowerBound)...Double(BatteryCareSettings.limitRange.upperBound)) { editing in
                guard !editing, let value = limitDraft else { return }
                service.update { $0.limit = Int(value.rounded()) }
                limitDraft = nil
            }
            .controlSize(.small)
            caption(s.limitCaption)
            HStack(spacing: 6) {
                if case .discharge = service.activity {
                    Button(s.stop, action: service.stopActivity)
                } else if service.capabilities.canDischarge, !settings.automaticDischarge, percent > settings.limit {
                    Button(s.discharge) { service.discharge() }
                }
                if service.activity == .topUp {
                    Button(s.endTopUp) { service.topUp(false) }
                } else {
                    Button(s.topUp) { service.topUp(true) }
                }
                if case .calibration = service.activity {
                    Button(s.stopCalibration, action: service.stopActivity)
                } else {
                    Button(s.calibrate, action: service.calibrate)
                }
                Button(s.pauseHere, action: service.pauseHere)
            }
            .controlSize(.small)
            .disabled(!canControl)
            if !service.capabilities.canDischarge { caption(s.dischargeUnavailable) }
            caption(s.calibrationCaption)
        }
    }

    // MARK: Options

    private func binding<T>(_ path: WritableKeyPath<BatteryCareSettings, T>) -> Binding<T> {
        Binding(get: { service.settings[keyPath: path] },
                set: { value in service.update { $0[keyPath: path] = value } })
    }

    private var optionsCard: some View {
        let settings = service.settings
        return VStack(alignment: .leading, spacing: 8) {
            Text(s.options).font(.system(size: 11.5, weight: .semibold))
            toggle(s.enabled, binding(\.enabled), caption: s.enabledCaption)
            toggle(s.fixReadings, binding(\.fixReadings), caption: s.fixReadingsCaption)
            toggle(s.sailing, binding(\.sailing), caption: s.sailingCaption)
            if settings.sailing {
                Stepper(String(format: s.sailingWidthFormat, settings.sailingWidth), value: binding(\.sailingWidth),
                        in: BatteryCareSettings.sailingWidthRange)
                    .font(.system(size: 10.5))
                    .controlSize(.small)
            }
            toggle(s.heatProtection, binding(\.heatProtection), caption: s.heatCaption)
            if settings.heatProtection {
                Stepper(MetricFormat.temperature(settings.maxTemperature, unit: unit),
                        value: binding(\.maxTemperature), in: BatteryCareSettings.temperatureRange, step: 1)
                    .font(.system(size: 10.5))
                    .controlSize(.small)
            }
            if service.capabilities.canDischarge {
                toggle(s.automaticDischarge, binding(\.automaticDischarge), caption: s.automaticDischargeCaption)
            }
            toggle(s.stopWhenSleeping, binding(\.stopChargingWhenSleeping))
            toggle(s.stayAwake, binding(\.disableSleepUntilLimit), caption: s.stayAwakeCaption)
            if service.capabilities.hasMagSafeLED {
                toggle(s.magSafe, binding(\.magSafeLED), caption: s.magSafeCaption)
            }
            Picker(s.lowPowerMode, selection: binding(\.lowPowerMode)) {
                Text(s.lowPowerUnchanged).tag(BatteryLowPowerPreference.unchanged)
                Text(s.lowPowerAlwaysOff).tag(BatteryLowPowerPreference.alwaysOff)
                Text(s.lowPowerAlwaysOn).tag(BatteryLowPowerPreference.alwaysOn)
                Text(s.lowPowerOnBattery).tag(BatteryLowPowerPreference.onBattery)
                Text(s.lowPowerOnAdapter).tag(BatteryLowPowerPreference.onAdapter)
            }
            .font(.system(size: 10.5))
            .controlSize(.small)
            Toggle(s.notifications, isOn: $notifications)
                .font(.system(size: 10.5, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .disabled(!canControl && service.helperInstalled)
    }

    // MARK: Sleep control

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.sleepTitle).font(.system(size: 11.5, weight: .semibold))
            if keepAwake.isActive {
                caption(keepAwake.endDate.map {
                    String(format: s.sleepUntilFormat, $0.formatted(date: .omitted, time: .shortened))
                } ?? s.sleepIndefinite)
                Button(s.letItSleep, action: service.letSleep).controlSize(.small)
            } else {
                caption(s.sleepIdle)
                HStack(spacing: 6) {
                    Button(s.thirtyMinutes) { service.keepAwake(minutes: 30) }
                    Button(s.oneHour) { service.keepAwake(minutes: 60) }
                    Button(s.threeHours) { service.keepAwake(minutes: 180) }
                    Button(s.indefinitely) { service.keepAwake(minutes: 0) }
                }
                .controlSize(.small)
            }
            toggle(s.sleepEndUnplugged, $sleepEndsUnplugged)
            Stepper(String(format: s.sleepEndBatteryFormat, keepAwakeBatteryLimit),
                    value: $keepAwakeBatteryLimit, in: 5...95, step: 5)
                .font(.system(size: 10.5))
                .controlSize(.small)
        }
    }

    // MARK: Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.health).font(.system(size: 11.5, weight: .semibold))
            if let reading {
                if let health = reading.healthPercent, let max = reading.maxCapacity, let design = reading.designCapacity {
                    row(s.maximumCapacity, String(format: s.capacityFormat, health, max, design))
                }
                if let cycles = reading.cycleCount {
                    row(s.cycles, reading.designCycleCount.map { String(format: s.cyclesFormat, cycles, $0) } ?? "\(cycles)")
                }
                row(s.condition, reading.serviceRecommended ? s.conditionService : s.conditionNormal,
                    color: reading.serviceRecommended ? .orange : nil)
                if let temperature = reading.temperature { row(s.temperature, MetricFormat.temperature(temperature, unit: unit)) }
                if let voltage = reading.voltage { row(s.voltage, volts(voltage)) }
                if !reading.cellVoltages.isEmpty {
                    row(s.cells, reading.cellVoltages.map(volts).joined(separator: "  "))
                }
                if let resting = BatteryChargeEstimate.restingPercent(reading) {
                    row(s.cellEstimate, "\(resting)%", color: readingIsWrong ? .orange : nil)
                }
                if let amperage = reading.amperage { row(s.current, "\(amperage) mA") }
                if let hardware = reading.hardwarePercent { row(s.hardwarePercentage, "\(hardware)%") }
                if let name = reading.adapterName ?? reading.adapterWatts.map({ "\($0) W" }) {
                    row(s.charger, name)
                }
                if let minutes = reading.minutesToEmpty { row(s.timeToEmpty, duration(minutes)) }
                if let minutes = reading.minutesToFull, reading.isCharging { row(s.timeToFull, duration(minutes)) }
            } else {
                caption(s.unknown)
            }
        }
    }

    private func volts(_ millivolts: Int) -> String {
        String(format: "%.2f V", locale: l10n.language.formattingLocale(), Double(millivolts) / 1000)
    }

    private func duration(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }

    // MARK: Energy

    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.energyTitle).font(.system(size: 11.5, weight: .semibold))
            if service.energyApps.isEmpty {
                caption(s.energyNone)
            }
            ForEach(service.energyApps) { app in
                HStack(spacing: 6) {
                    if let icon = NSRunningApplication(processIdentifier: app.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(app.name).font(.system(size: 10.5)).lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f", locale: l10n.language.formattingLocale(), app.value)).font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(s.quit) { service.quitApp(app.pid) }.controlSize(.mini)
                }
            }
        }
    }

    // MARK: Schedule

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(s.scheduleTitle).font(.system(size: 11.5, weight: .semibold))
            if service.tasks.isEmpty, draft == nil { caption(s.noTasks) }
            ForEach(service.tasks) { task in taskRow(task) }
            if let draft {
                BatteryScheduleEditor(task: draft, strings: s,
                                      onSave: { service.addTask($0); self.draft = nil },
                                      onCancel: { self.draft = nil })
            } else {
                HStack(spacing: 6) {
                    Button(s.addTask) {
                        draft = BatteryScheduleTask(action: .setLimit(service.settings.limit), repeats: .daily,
                                                    start: BatteryScheduleSupport.nextMorning(now: Date()))
                    }
                    Button(s.monthlyCalibration) {
                        service.addTask(BatteryScheduleSupport.monthlyCalibration(now: Date()))
                    }
                }
                .controlSize(.small)
            }
            toggle(s.catchUp, $catchUp, caption: s.catchUpCaption)
            if !service.history.isEmpty {
                Text(s.recentRuns).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(service.history.prefix(5)) { run in
                    HStack {
                        Text(Self.actionTitle(run.action, s)).font(.system(size: 10))
                        Spacer()
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)
                             + (run.caughtUp ? " (\(s.late))" : ""))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: BatteryScheduleTask) -> some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { task.enabled }, set: { on in
                var changed = task
                changed.enabled = on
                service.updateTask(changed)
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            VStack(alignment: .leading, spacing: 1) {
                Text(Self.actionTitle(task.action, s)).font(.system(size: 10.5, weight: .medium))
                Text(Self.repeatTitle(task.repeats, s) + " · " + (
                    BatteryScheduleSupport.nextOccurrence(of: task, after: Date()).map {
                        String(format: s.nextFormat, $0.formatted(date: .abbreviated, time: .shortened))
                    } ?? s.finished))
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { service.removeTask(task.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(s.delete)
        }
    }

    static func actionTitle(_ action: BatteryScheduleAction, _ s: BatteryCareFeatureStrings) -> String {
        switch action {
        case .setLimit(let percent): return String(format: s.setLimitFormat, percent)
        case .calibrate: return s.startCalibration
        case .topUp: return s.topUp
        case .pauseCharging: return s.pauseCharging
        case .dischargeTo(let percent): return String(format: s.dischargeToFormat, percent)
        case .lowPowerOn: return s.lowPowerOn
        case .lowPowerOff: return s.lowPowerOff
        }
    }

    static func repeatTitle(_ repeats: BatteryScheduleRepeat, _ s: BatteryCareFeatureStrings) -> String {
        switch repeats {
        case .never: return s.repeatNever
        case .daily: return s.repeatDaily
        case .weekdays: return s.repeatWeekdays
        case .weekly: return s.repeatWeekly
        case .everyTwoWeeks: return s.repeatTwoWeeks
        case .monthly: return s.repeatMonthly
        case .yearly: return s.repeatYearly
        }
    }

    // MARK: Shortcuts

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.shortcutsTitle).font(.system(size: 11.5, weight: .semibold))
            caption(s.shortcutsCaption)
            ForEach(BatteryCareCLI.commands.indices, id: \.self) { index in
                let entry = BatteryCareCLI.commands[index]
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("battery \(entry.command)").font(.system(size: 10, design: .monospaced))
                        Text(entry.summary).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(copiedCommand == entry.command ? s.copied : s.copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(BatteryCareCLI.shellCommand(entry.command), forType: .string)
                        copiedCommand = entry.command
                    }
                    .controlSize(.mini)
                }
            }
        }
    }

    private var removeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption(s.removeHelperCaption)
            Button(s.removeHelper, action: service.removeHelper)
                .controlSize(.small)
                .disabled(service.isInstalling)
        }
    }

    // MARK: Pieces

    private func card(_ content: some View) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).panelCard()
    }

    private func toggle(_ title: String, _ isOn: Binding<Bool>, caption text: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .font(.system(size: 10.5, weight: .medium))
                .toggleStyle(.switch)
                .controlSize(.mini)
            if let text { caption(text) }
        }
    }

    private func caption(_ text: String, color: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(color ?? Color.secondary.opacity(0.84))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(color ?? .primary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The charge as a bar, with the limit marked and Sailing's range shaded.
private struct BatteryLimitBar: View {
    let percent: Int
    let limit: Int
    let sailingFloor: Int?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                if let sailingFloor, sailingFloor < limit {
                    Rectangle().fill(color.opacity(0.18))
                        .frame(width: width * CGFloat(limit - sailingFloor) / 100)
                        .offset(x: width * CGFloat(sailingFloor) / 100)
                }
                Capsule().fill(color.opacity(0.85))
                    .frame(width: max(4, width * CGFloat(min(max(percent, 0), 100)) / 100))
                Rectangle().fill(Color.primary.opacity(0.75))
                    .frame(width: 2, height: proxy.size.height + 4)
                    .offset(x: width * CGFloat(limit) / 100 - 1)
            }
            .clipShape(Capsule())
        }
    }
}

/// The task editor: an action, its percentage, how it repeats and when.
private struct BatteryScheduleEditor: View {
    @State var task: BatteryScheduleTask
    let strings: BatteryCareFeatureStrings
    let onSave: (BatteryScheduleTask) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(strings.action, selection: Binding(
                get: { BatteryScheduleAction.all.first { $0.isSameKind(as: task.action) } ?? task.action },
                set: { picked in task.action = picked.withPercent(task.action.percent ?? picked.percent ?? 80) })) {
                ForEach(BatteryScheduleAction.all, id: \.self) { action in
                    Text(BatteryCareView.actionTitle(action.percent == nil ? action : action.withPercent(
                        task.action.percent ?? action.percent ?? 80), strings)).tag(action)
                }
            }
            if let percent = task.action.percent {
                Stepper("\(percent)%", value: Binding(get: { percent }, set: { task.action = task.action.withPercent($0) }),
                        in: BatteryCareSettings.limitRange, step: 5)
            }
            Picker(strings.repeats, selection: $task.repeats) {
                ForEach(BatteryScheduleRepeat.allCases, id: \.self) { repeats in
                    Text(BatteryCareView.repeatTitle(repeats, strings)).tag(repeats)
                }
            }
            DatePicker(strings.starts, selection: $task.start)
            if task.repeats == .weekly {
                HStack(spacing: 3) {
                    ForEach(1...7, id: \.self) { day in
                        let name = Calendar.current.veryShortWeekdaySymbols[day - 1]
                        Toggle(name, isOn: Binding(get: { task.weekdays.contains(day) }, set: { on in
                            if on { task.weekdays.insert(day) } else { task.weekdays.remove(day) }
                        }))
                        .toggleStyle(.button)
                    }
                }
            }
            HStack {
                Button(strings.cancel, action: onCancel)
                Button(strings.add) { onSave(task) }.buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 10.5))
        .controlSize(.small)
    }
}

/// AlDente's Power Flow: where the watts come from on the left and where
/// they go on the right, as bands as wide as their share.
struct BatteryPowerFlowView: View {
    let power: PowerReading?
    let strings: BatteryCareFeatureStrings

    var body: some View {
        let charger = max(power?.adapterWatts ?? 0, 0)
        let batteryFlow = power?.batteryWatts ?? 0
        let fromBattery = max(-batteryFlow, 0)
        let intoBattery = max(batteryFlow, 0)
        let mac = max(power?.systemWatts ?? max(charger - intoBattery, 0) + fromBattery, 0)
        let sources: [(String, String, Double)] = [
            (strings.charger, "powerplug.fill", charger), (strings.battery, "battery.75", fromBattery),
        ].filter { $0.2 > 0.05 }
        let sinks: [(String, String, Double)] = [
            (strings.mac, "laptopcomputer", mac), (strings.battery, "battery.100.bolt", intoBattery),
        ].filter { $0.2 > 0.05 }
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.powerFlow).font(.system(size: 11.5, weight: .semibold))
            if sources.isEmpty || sinks.isEmpty {
                Text(power?.adapterWatts == nil && charger == 0 ? strings.noCharger : "-")
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 0) {
                    labels(sources, alignment: .leading)
                    Canvas { context, size in
                        draw(context: context, size: size, sources: sources.map(\.2), sinks: sinks.map(\.2),
                             sinkIsBattery: sinks.map { $0.1 == "battery.100.bolt" })
                    }
                    .frame(height: 54)
                    labels(sinks, alignment: .trailing)
                }
            }
        }
    }

    private func labels(_ nodes: [(String, String, Double)], alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(nodes.indices, id: \.self) { index in
                let node = nodes[index]
                VStack(alignment: alignment, spacing: 0) {
                    Label(node.0, systemImage: node.1).font(.system(size: 9.5)).foregroundStyle(.secondary)
                    Text(MetricFormat.watts(node.2)).font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                }
            }
        }
        .frame(width: 74, alignment: alignment == .leading ? .leading : .trailing)
    }

    /// Bands fill each source in turn, then each sink in turn, so their
    /// widths add up on both sides.
    private func draw(context: GraphicsContext, size: CGSize, sources: [Double], sinks: [Double],
                      sinkIsBattery: [Bool]) {
        let total = max(sources.reduce(0, +), sinks.reduce(0, +), 0.1)
        let scale = (size.height - 4) / CGFloat(total)
        var flows: [(Double, Int, Int)] = []
        var remaining = sinks
        for (sourceIndex, available) in sources.enumerated() {
            var watts = available
            for sinkIndex in remaining.indices where watts > 0.001 && remaining[sinkIndex] > 0.001 {
                let share = min(watts, remaining[sinkIndex])
                flows.append((share, sourceIndex, sinkIndex))
                watts -= share
                remaining[sinkIndex] -= share
            }
        }
        var leftY: CGFloat = 2
        var rightOffsets = Array(repeating: CGFloat(0), count: sinks.count)
        let rightStarts: [CGFloat] = sinks.indices.map { index in 2 + CGFloat(sinks.prefix(index).reduce(0, +)) * scale }
        for (watts, source, sink) in flows {
            let height = CGFloat(watts) * scale
            let rightY = rightStarts[sink] + rightOffsets[sink]
            rightOffsets[sink] += height
            var path = Path()
            path.move(to: CGPoint(x: 0, y: leftY))
            path.addCurve(to: CGPoint(x: size.width, y: rightY),
                          control1: CGPoint(x: size.width / 2, y: leftY),
                          control2: CGPoint(x: size.width / 2, y: rightY))
            path.addLine(to: CGPoint(x: size.width, y: rightY + height))
            path.addCurve(to: CGPoint(x: 0, y: leftY + height),
                          control1: CGPoint(x: size.width / 2, y: rightY + height),
                          control2: CGPoint(x: size.width / 2, y: leftY + height))
            path.closeSubpath()
            let color: Color = source == 1 ? .yellow : (sinkIsBattery[sink] ? .green : .teal)
            context.fill(path, with: .color(color.opacity(0.55)))
            leftY += height
        }
    }
}
