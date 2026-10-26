// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (Core/HistoryStore.swift) into Vorssaint + VoiceOS.

import Foundation

enum VOStorage {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VoiceOS Clone", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let modelsDirectory: URL = {
        let dir = directory.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Local-only transcript history (never leaves the Mac).
@MainActor
final class VOHistoryStore: ObservableObject {
    static let shared = VOHistoryStore()
    @Published private(set) var items: [VOHistoryItem] = []

    private var url: URL { VOStorage.directory.appendingPathComponent("history.json") }

    private init() {
        if let data = try? Data(contentsOf: url) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            items = (try? dec.decode([VOHistoryItem].self, from: data)) ?? []
        }
    }

    func add(_ item: VOHistoryItem) {
        guard VOSettings.shared.saveHistory else { return }
        items.insert(item, at: 0)
        if items.count > 5000 { items.removeLast(items.count - 5000) }
        save()
    }

    func delete(_ item: VOHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(items) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: - Stats

    var totalWords: Int { items.reduce(0) { $0 + $1.words } }
    var totalSessions: Int { items.count }
    var speakingSeconds: Double { items.reduce(0) { $0 + $1.duration } }

    /// Time saved vs typing the same words at 40 wpm.
    var timeSavedMinutes: Double {
        let typing = Double(totalWords) / 40.0
        return max(0, typing - speakingSeconds / 60.0)
    }

    var averageWPM: Int {
        let mins = items.filter { $0.mode != .agent }.reduce(0.0) { $0 + $1.duration } / 60
        let words = items.filter { $0.mode != .agent }.reduce(0) { $0 + $1.words }
        return mins > 0.05 ? Int(Double(words) / mins) : 0
    }

    var streakDays: Int {
        let cal = Calendar.current
        let days = Set(items.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    func wordsPerDay(last n: Int) -> [(day: Date, words: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets: [Date: Int] = [:]
        for it in items { buckets[cal.startOfDay(for: it.date), default: 0] += it.words }
        return (0..<n).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today)!
            return (d, buckets[d] ?? 0)
        }
    }

    func appUsage(limit: Int = 6) -> [(app: String, bundleID: String?, count: Int)] {
        var counts: [String: (String?, Int)] = [:]
        for it in items {
            let c = counts[it.appName] ?? (it.bundleID, 0)
            counts[it.appName] = (c.0 ?? it.bundleID, c.1 + 1)
        }
        return counts.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.2 > $1.2 }.prefix(limit).map { $0 }
    }

    func modeUsage() -> [(mode: VOSessionMode, count: Int)] {
        VOSessionMode.allCases.map { m in (m, items.filter { $0.mode == m }.count) }
    }

    func hourHistogram() -> [Int] {
        var h = Array(repeating: 0, count: 24)
        for it in items { h[Calendar.current.component(.hour, from: it.date)] += 1 }
        return h
    }
}
