// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Battery Care's words. English for now: every language reads these until
/// they are translated.
struct BatteryCareFeatureStrings {
    let title = "Battery Care"
    let battery = "Battery"
    let pageSummary = "The charge limit, what the battery is doing and its health."
    let hardwareFormat = "Hardware %d%%"

    // What it is doing
    let stateOff = "Battery Care is off, so the Mac charges as usual"
    let stateChargingFormat = "Charging to %d%%"
    let stateHoldingFormat = "Holding at the %d%% limit"
    let statePausedAboveFormat = "Not charging: above the %d%% limit"
    let stateFull = "Fully charged"
    let stateSailingFormat = "Sailing: charges again at %d%%"
    let stateDischargingFormat = "Running on battery down to %d%%"
    let stateToppingUp = "Topping up to 100%"
    let stateHeatFormat = "Paused while the battery cools (%@)"
    let stateCalibratingFormat = "Calibrating, step %d of 4: %@"
    let stateFixingFormat = "Fixing the battery reading: %@"
    let stepChargeFull = "charging to full"
    let stepDischargeLow = "running down to 10%"
    let stepRechargeFull = "charging to full again"
    let stepReturn = "returning to the limit"
    let stateOnBattery = "On battery"
    let stateUnplug = "Unplug the charger to run the battery down"
    let statePlugIn = "Plug in the charger to continue"
    let stateSleepPaused = "Paused while the Mac sleeps"

    // The helper
    let helperNeeded = "Holding a limit needs Battery Care’s helper, which runs as administrator. Someone with an administrator name and password approves it once."
    let helperOutdated = "A newer helper is ready. An administrator approves it once."
    let helperUnreachable = "The helper is installed but isn’t answering."
    let installHelper = "Install Helper"
    let updateHelper = "Update Helper"
    let waitingForApproval = "Waiting for approval…"
    let removeHelper = "Remove Helper"
    let removeHelperCaption = "Hands charging back to macOS and removes the helper."
    let installFailed = "The helper wasn’t installed."
    let otherLimiterFormat = "%@ is also controlling charging. Quit it so the two don’t fight over the battery."
    let quitOtherFormat = "Quit %@"
    let refusedChange = "The charging controller refused a change."

    // Battery check
    let checkTitle = "Battery Check"
    let wrongReadingFormat = "The battery reports %d%%, but its cells read %@ V each, which is close to empty. That’s why the Mac runs out minutes after unplugging, and why a charge limit kept it from charging."
    let wrongReadingFix = "Charging to full once lets the battery measure itself again. Afterwards, check how long it lasts unplugged."
    let wrongReadingNoHelper = "Install the helper above, or set your other charge limiter to 100% for now."
    let wrongReadingFixing = "Charging to full now. Leave the charger plugged in."
    let chargeToFull = "Charge to Full"
    let serviceFormat = "macOS recommends servicing this battery. It holds %d%% of its original capacity after %d cycles. A new battery is the lasting fix."
    let weakBatteryFormat = "On %@ the battery couldn’t keep the Mac running at %d%%. It needs replacing."
    let noProblems = "No problems found."

    // Charge limit and actions
    let limitTitle = "Charge Limit"
    let limitCaption = "Charging stops here while plugged in. 50 to 80% is gentlest on the battery."
    let discharge = "Discharge"
    let stop = "Stop"
    let topUp = "Top Up"
    let endTopUp = "End Top Up"
    let calibrate = "Calibrate"
    let stopCalibration = "Stop Calibration"
    let pauseHere = "Pause Here"
    let dischargeUnavailable = "This Mac can’t run on battery while plugged in, so unplug it to bring the charge down."
    let calibrationCaption = "Calibration charges to full, runs down to 10%, charges to full again and returns to the limit. Once a month keeps the readings accurate."

    // Options
    let options = "Options"
    let enabled = "Control Charging"
    let enabledCaption = "Off hands charging back to macOS."
    let sailing = "Sailing"
    let sailingCaption = "Lets the charge drift down this far below the limit before charging again."
    let sailingWidthFormat = "%d%% below"
    let heatProtection = "Heat Protection"
    let heatCaption = "Pauses charging while the battery is hotter than this."
    let automaticDischarge = "Automatic Discharge"
    let automaticDischargeCaption = "Runs on battery while plugged in whenever the charge is above the limit."
    let stopWhenSleeping = "Stop Charging when Sleeping"
    let stayAwake = "Stay Awake until the Limit"
    let stayAwakeCaption = "Keeps the Mac awake, even with the lid closed, until it reaches the limit."
    let fixReadings = "Fix Wrong Readings"
    let fixReadingsCaption = "Charges to full once when the cells hold far less than the battery reports."
    let magSafe = "MagSafe Light"
    let magSafeCaption = "Green at the limit, orange on the way to it."
    let lowPowerMode = "Low Power Mode"
    let lowPowerUnchanged = "Leave as Set"
    let lowPowerAlwaysOff = "Always Off"
    let lowPowerAlwaysOn = "Always On"
    let lowPowerOnBattery = "Only on Battery"
    let lowPowerOnAdapter = "Only on Power Adapter"
    let notifications = "Notifications"

    // Power flow
    let powerFlow = "Power Flow"
    let charger = "Charger"
    let mac = "Mac"
    let noCharger = "Not plugged in"

    // Health
    let health = "Battery Health"
    let maximumCapacity = "Maximum capacity"
    let capacityFormat = "%d%% (%d of %d mAh)"
    let cycles = "Cycles"
    let cyclesFormat = "%d of %d"
    let condition = "Condition"
    let conditionNormal = "Normal"
    let conditionService = "Service recommended"
    let temperature = "Temperature"
    let voltage = "Voltage"
    let cells = "Cells"
    let current = "Current"
    let hardwarePercentage = "Hardware percentage"
    let cellEstimate = "Charge by cell voltage"
    let timeToEmpty = "Time to empty"
    let timeToFull = "Time to full"
    let unknown = "Unknown"

    // Energy
    let energyTitle = "Apps Using Significant Energy"
    let energyNone = "No app is using much energy."
    let quit = "Quit"

    // Sleep control
    let sleepTitle = "Sleep Control"
    let sleepIdle = "The Mac sleeps as usual."
    let sleepUntilFormat = "Staying awake until %@"
    let sleepIndefinite = "Staying awake"
    let letItSleep = "Let It Sleep"
    let sleepEndUnplugged = "End when unplugged"
    let sleepEndBatteryFormat = "End on battery at %d%%"
    let thirtyMinutes = "30 min"
    let oneHour = "1 hour"
    let threeHours = "3 hours"
    let indefinitely = "∞"

    // Schedule
    let scheduleTitle = "Schedule"
    let addTask = "Add Task"
    let monthlyCalibration = "Monthly Calibration"
    let noTasks = "No scheduled tasks."
    let catchUp = "Catch Up on Missed Tasks"
    let catchUpCaption = "Runs a task the Mac slept through as soon as it wakes. Best when the Mac is used most days."
    let recentRuns = "Recent Runs"
    let nextFormat = "Next %@"
    let finished = "Done"
    let late = "late"
    let action = "Action"
    let repeats = "Repeat"
    let starts = "Starts"
    let add = "Add"
    let cancel = "Cancel"
    let delete = "Delete"
    let setLimitFormat = "Set Limit to %d%%"
    let startCalibration = "Start Calibration"
    let pauseCharging = "Pause Charging"
    let dischargeToFormat = "Discharge to %d%%"
    let lowPowerOn = "Turn On Low Power Mode"
    let lowPowerOff = "Turn Off Low Power Mode"
    let repeatNever = "Once"
    let repeatDaily = "Daily"
    let repeatWeekdays = "Weekdays"
    let repeatWeekly = "Weekly"
    let repeatTwoWeeks = "Every 2 Weeks"
    let repeatMonthly = "Monthly"
    let repeatYearly = "Yearly"

    // Shortcuts
    let shortcutsTitle = "Shortcuts"
    let shortcutsCaption = "In Shortcuts, add a Run Shell Script action with one of these commands. The get commands print their answer for the next action."
    let copy = "Copy"
    let copied = "Copied"

    // Notifications
    let notifyLimitFormat = "Charging paused at the %d%% limit."
    let notifyDischargeFormat = "Discharge finished at %d%%."
    let notifyDischargeStoppedFormat = "Discharge stopped at %d%%: the battery’s voltage got too low."
    let notifyCalibration = "Calibration finished."
    let notifyFixStarted = "The battery reported far more charge than it holds. Charging to full to fix the reading."
    let notifyFixFinished = "The battery reading is fixed and the limit is back."
    let notifyHeat = "Charging paused: the battery is too hot."
    let notifyWeakFormat = "The battery couldn’t keep the Mac running at %d%%. It needs replacing."

    static let enUS = BatteryCareFeatureStrings()
}

extension FeatureStrings {
    static func batteryCare(_ language: AppLanguage) -> BatteryCareFeatureStrings {
        .enUS
    }
}
