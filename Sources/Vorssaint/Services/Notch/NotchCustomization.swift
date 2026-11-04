// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The parts of the island's home, each of which can be removed.
enum NotchHubWidget: String, CaseIterable {
    case calendar, camera, actions, nowPlaying
}

/// Anything the person can take off the island and put back: a part of the
/// home, a shortcut on it, a page, or a control on the Controls page.
enum NotchRemovable: Hashable, Identifiable {
    case widget(NotchHubWidget)
    case homeAction(NotchControlItem)
    case page(NotchModule)
    case control(NotchControlItem)

    var id: String {
        switch self {
        case .widget(let widget): return "widget." + widget.rawValue
        case .homeAction(let item): return "home." + item.rawValue
        case .page(let module): return "page." + module.rawValue
        case .control(let item): return "control." + item.rawValue
        }
    }
}

/// Removing writes the same lists Settings uses for pages and controls, and
/// two of the home's own, so either place shows the other's changes. What
/// stays fills the room: the island reads these lists as it draws.
enum NotchCustomization {
    static func isRemoved(_ item: NotchRemovable, in defaults: UserDefaults = .standard) -> Bool {
        let (key, value) = entry(item)
        return list(key, defaults).contains(value)
    }

    static func remove(_ item: NotchRemovable, in defaults: UserDefaults = .standard) {
        let (key, value) = entry(item)
        var values = list(key, defaults)
        guard !values.contains(value) else { return }
        values.append(value)
        defaults.set(values.joined(separator: ","), forKey: key)
    }

    static func restore(_ item: NotchRemovable, in defaults: UserDefaults = .standard) {
        let (key, value) = entry(item)
        let values = list(key, defaults)
        guard values.contains(value) else { return }
        defaults.set(values.filter { $0 != value }.joined(separator: ","), forKey: key)
    }

    /// What can be put back, each only where its feature is on, so adding it
    /// shows it at once: the home's parts, its shortcuts, pages, controls.
    static func addable(in defaults: UserDefaults = .standard, cameraEnabled: Bool = true) -> [NotchRemovable] {
        let widgets = NotchHubWidget.allCases.filter { $0 != .camera || cameraEnabled }.map(NotchRemovable.widget)
        let actions = homeActionOrder.filter { $0.isAvailable(in: defaults) }.map(NotchRemovable.homeAction)
        let pages = NotchModule.allCases.filter { $0 != .voice && $0.isAvailable(in: defaults) }.map(NotchRemovable.page)
        let controls = NotchControlItem.allCases.filter { $0.isAvailable(in: defaults) }.map(NotchRemovable.control)
        return (widgets + actions + pages + controls).filter { isRemoved($0, in: defaults) }
    }

    /// The home's shortcuts, most used first; the home shows as many as fit.
    static let homeActionOrder: [NotchControlItem] = [
        .screenshot, .recording, .keepAwake, .battery, .fans, .microphone, .scratchpad, .commandBar, .timer, .toggles,
        .speedTest, .mixer, .panel, .calendar, .music,
    ]

    static func homeActions(in defaults: UserDefaults = .standard) -> [NotchControlItem] {
        homeActionOrder.filter { $0.isAvailable(in: defaults) && !isRemoved(.homeAction($0), in: defaults) }
    }

    /// How the home lays out what is left: the calendar beside a column of
    /// the camera and the shortcuts, or, without the calendar, the shortcuts
    /// spread across its room beside the camera.
    struct HomeLayout: Equatable {
        var calendar: Bool
        var camera: Bool
        var actions: Bool
        var actionColumns: Int
        var actionRows: Int
        var isEmpty: Bool { !calendar && !camera && !actions }
    }

    static func homeLayout(cameraEnabled: Bool, in defaults: UserDefaults = .standard) -> HomeLayout {
        let calendar = !isRemoved(.widget(.calendar), in: defaults)
        let camera = cameraEnabled && !isRemoved(.widget(.camera), in: defaults)
        let actions = !isRemoved(.widget(.actions), in: defaults) && !homeActions(in: defaults).isEmpty
        let columns = calendar ? 3 : (camera ? 3 : 6)
        let rows = calendar && camera ? 2 : 4
        return HomeLayout(calendar: calendar, camera: camera, actions: actions, actionColumns: columns, actionRows: rows)
    }

    private static func entry(_ item: NotchRemovable) -> (key: String, value: String) {
        switch item {
        case .widget(let widget): return (DefaultsKey.notchHubHiddenWidgets, widget.rawValue)
        case .homeAction(let control): return (DefaultsKey.notchHubHiddenActions, control.rawValue)
        case .page(let module): return (DefaultsKey.notchHiddenModules, module.rawValue)
        case .control(let control): return (DefaultsKey.notchHiddenControls, control.rawValue)
        }
    }

    private static func list(_ key: String, _ defaults: UserDefaults) -> [String] {
        let fallback = key == DefaultsKey.notchHiddenControls ? NotchControlItem.defaultHidden : ""
        return (defaults.string(forKey: key) ?? fallback).split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }
}
