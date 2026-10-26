// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/InsightsView.swift) into Vorssaint + VoiceOS.

import SwiftUI
import Charts

struct VOInsightsView: View {
    @ObservedObject private var history = VOHistoryStore.shared
    @ObservedObject private var providers = VOProviderManager.shared

    var body: some View {
        VOPageScaffold(title: "Insights") {
            HStack(spacing: 14) {
                VOStatTile(symbol: "speedometer", title: "Avg. speed", value: history.averageWPM > 0 ? "\(history.averageWPM) wpm" : "—")
                VOStatTile(symbol: "text.word.spacing", title: "This week", value: wordsThisWeek.formatted())
                VOStatTile(symbol: "flame", title: "Streak", value: "\(history.streakDays) day\(history.streakDays == 1 ? "" : "s")")
                VOStatTile(symbol: "clock", title: "Time saved", value: VODashboardView.duration(history.timeSavedMinutes))
            }

            VOCard {
                HStack {
                    Text("Words per day").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("Last 14 days").font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                }
                Chart(history.wordsPerDay(last: 14), id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Words", d.words))
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0x8DB8FF), VOTheme.accent], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(5)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true).foregroundStyle(VOTheme.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel().foregroundStyle(VOTheme.secondary)
                    }
                }
                .frame(height: 200)
            }

            HStack(alignment: .top, spacing: 16) {
                VOCard {
                    Text("When you talk").font(.system(size: 15, weight: .semibold))
                    let hours = history.hourHistogram()
                    Chart(Array(hours.enumerated()), id: \.offset) { h in
                        BarMark(x: .value("Hour", h.offset), y: .value("Sessions", h.element))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .cornerRadius(2)
                    }
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                            AxisValueLabel { if let i = v.as(Int.self) { Text(i == 0 ? "12a" : i < 12 ? "\(i)a" : i == 12 ? "12p" : "\(i - 12)p") } }
                                .foregroundStyle(VOTheme.secondary)
                        }
                    }
                    .chartYAxis(.hidden)
                    .frame(height: 120)
                }
                VOCard {
                    Text("Modes").font(.system(size: 15, weight: .semibold))
                    let modes = history.modeUsage().filter { $0.count > 0 }
                    if modes.isEmpty {
                        Text("No sessions yet.").font(.system(size: 13)).foregroundColor(VOTheme.secondary).frame(height: 120)
                    } else {
                        Chart(modes, id: \.mode) { m in
                            SectorMark(angle: .value("Count", m.count), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(by: .value("Mode", m.mode.label))
                                .cornerRadius(4)
                        }
                        .chartForegroundStyleScale(["Dictation Mode": Color.white.opacity(0.85), "Edit Mode": Color(hex: 0x8DB8FF), "Assistant Mode": VOTheme.accent])
                        .chartLegend(position: .trailing)
                        .frame(height: 120)
                    }
                }
            }

            HStack {
                VOSectionLabel(text: "AI usage")
                Spacer()
                Button {
                    providers.refreshUsage()
                } label: {
                    Label(providers.loadingUsage ? "Refreshing…" : "Refresh plan limits", systemImage: "arrow.clockwise")
                }
                .buttonStyle(VOSecondaryButtonStyle())
                .disabled(providers.loadingUsage)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(VOProviderID.allCases) { p in usageCard(p) }
            }
        }
    }

    private var wordsThisWeek: Int { history.wordsPerDay(last: 7).reduce(0) { $0 + $1.words } }

    private func usageCard(_ p: VOProviderID) -> some View {
        let t = providers.totals(for: p)
        return VOCard(padding: 18) {
            HStack(spacing: 10) {
                VOProviderLogo(provider: p, size: 26)
                Text(p.displayName).font(.system(size: 15, weight: .semibold))
            }
            VOPlanUsageView(usage: p.isLocal ? VOPlanUsage(note: "Free — runs on this Mac, no limits.") : providers.planUsage[p])
            Divider().overlay(Color.white.opacity(0.06))
            VStack(alignment: .leading, spacing: 6) {
                usageRow("Requests (30d)", "\(t.requests)")
                usageRow("Avg. response", t.requests > 0 ? String(format: "%.1fs", locale: .current, t.seconds / Double(t.requests)) : "—")
                usageRow("Failed", "\(t.failures)")
                usageRow("Text sent / received", "\(Self.compact(t.inputChars)) / \(Self.compact(t.outputChars)) chars")
            }
        }
    }

    private func usageRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
            Spacer()
            Text(v).font(.system(size: 12.5, weight: .medium))
        }
    }

    static func compact(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", locale: .current, Double(n) / 1_000_000) : n >= 1000 ? String(format: "%.1fk", locale: .current, Double(n) / 1000) : "\(n)"
    }
}

/// Plan limit meters (session / weekly) reported by CodexBar.
struct VOPlanUsageView: View {
    let usage: VOPlanUsage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let usage, !usage.meters.isEmpty {
                ForEach(usage.meters) { m in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(m.label).font(.system(size: 12.5))
                            Spacer()
                            Text("\(Int(m.usedPercent.rounded()))% used").font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(m.usedPercent > 85 ? VOTheme.orange : VOTheme.secondary)
                        }
                        VOUsageBar(fraction: m.usedPercent / 100, color: m.usedPercent > 85 ? VOTheme.orange : VOTheme.green, height: 5)
                        if let r = m.resets { Text("Resets \(r)").font(.system(size: 11)).foregroundColor(VOTheme.tertiary) }
                    }
                }
            } else {
                Text(usage?.note ?? "Plan limits not loaded yet.")
                    .font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
    }
}
