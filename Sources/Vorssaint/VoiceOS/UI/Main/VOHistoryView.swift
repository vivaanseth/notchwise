// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/HistoryView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VOHistoryView: View {
    @ObservedObject private var history = VOHistoryStore.shared
    @State private var query = ""
    @State private var filter: VOSessionMode? = nil
    @State private var expanded: UUID?
    @State private var confirmClear = false

    private var filtered: [VOHistoryItem] {
        history.items.filter { item in
            (filter == nil || item.mode == filter) &&
            (query.isEmpty || item.output.localizedCaseInsensitiveContains(query) || item.transcript.localizedCaseInsensitiveContains(query)
             || item.appName.localizedCaseInsensitiveContains(query))
        }
    }

    private var grouped: [(String, [VOHistoryItem])] {
        let cal = Calendar.current
        var order: [String] = []
        var dict: [String: [VOHistoryItem]] = [:]
        for it in filtered {
            let key: String
            if cal.isDateInToday(it.date) { key = "Today" }
            else if cal.isDateInYesterday(it.date) { key = "Yesterday" }
            else { key = it.date.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
            if dict[key] == nil { order.append(key) }
            dict[key, default: []].append(it)
        }
        return order.map { ($0, dict[$0]!) }
    }

    var body: some View {
        VOPageScaffold(title: "History") {
            if confirmClear {
                HStack(spacing: 10) {
                    Text("Delete all \(history.items.count) entries?").font(.system(size: 13)).foregroundColor(VOTheme.secondary)
                    Button("Cancel") { confirmClear = false }.buttonStyle(VOSecondaryButtonStyle())
                    Button("Delete all") { history.clear(); confirmClear = false }.buttonStyle(VOPrimaryButtonStyle())
                }
            } else {
                Button { confirmClear = true } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(VOSecondaryButtonStyle())
                    .disabled(history.items.isEmpty)
            }
        } content: {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(VOTheme.tertiary)
                    TextField("", text: $query, prompt: Text("Search transcripts").foregroundColor(VOTheme.tertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(VOTheme.field))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(VOTheme.border, lineWidth: 1))

                VOSegmentedPill(options: [(nil, "All"), (.dictation, "Dictation"), (.edit, "Edit"), (.agent, "Assistant")], selection: $filter, compact: true)
            }

            Text("Transcripts are stored only on this Mac.").font(.system(size: 12)).foregroundColor(VOTheme.tertiary)

            if filtered.isEmpty {
                VStack(spacing: 14) {
                    VOOrb(size: 56)
                    Text(history.items.isEmpty ? "Nothing here yet" : "No matches").font(.system(size: 17, weight: .semibold))
                    if history.items.isEmpty {
                        HStack(spacing: 6) {
                            Text("Press").foregroundColor(VOTheme.secondary)
                            VOKeyCap(label: "fn")
                            Text("and start speaking.").foregroundColor(VOTheme.secondary)
                        }
                        .font(.system(size: 14))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 70)
            }

            ForEach(grouped, id: \.0) { day, items in
                Text(day).font(.system(size: 13, weight: .semibold)).foregroundColor(VOTheme.secondary).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        row(item)
                        if i < items.count - 1 { Divider().overlay(Color.white.opacity(0.05)).padding(.leading, 86) }
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VOTheme.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            }
        }
    }

    private func row(_ item: VOHistoryItem) -> some View {
        let isOpen = expanded == item.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                Text(item.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12, weight: .medium)).foregroundColor(VOTheme.tertiary)
                    .frame(width: 56, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        VOAppIconView(bundleID: item.bundleID, symbol: "app", size: 16)
                        Text(item.appName).font(.system(size: 12, weight: .medium)).foregroundColor(VOTheme.secondary)
                        modeBadge(item.mode)
                        if let e = item.error {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(VOTheme.orange).help(e)
                        }
                    }
                    Text(item.output.isEmpty ? item.transcript : item.output)
                        .font(.system(size: 14)).foregroundColor(.white.opacity(0.92))
                        .lineLimit(isOpen ? nil : 2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    iconButton("doc.on.doc", "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.output.isEmpty ? item.transcript : item.output, forType: .string)
                    }
                    iconButton(isOpen ? "chevron.up" : "chevron.down", "Details") { expanded = isOpen ? nil : item.id }
                    iconButton("trash", "Delete") { history.delete(item) }
                }
            }
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    detail("What you said", item.transcript)
                    if let p = item.provider { detail("AI", "\(p)\(item.polished ? "" : " (not used)")") }
                    detail("Length", String(format: "%.1fs · %d words", locale: .current, item.duration, item.words))
                    if let e = item.error { detail("Problem", e) }
                }
                .padding(.leading, 70)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k).font(.system(size: 12)).foregroundColor(VOTheme.tertiary).frame(width: 96, alignment: .leading)
            Text(v).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary).textSelection(.enabled)
        }
    }

    private func modeBadge(_ m: VOSessionMode) -> some View {
        Text(m == .dictation ? "Dictation" : m == .edit ? "Edit" : "Assistant")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(m == .agent ? VOTheme.accent : .white.opacity(0.7))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(m == .agent ? VOTheme.accent.opacity(0.15) : Color.white.opacity(0.08)))
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundColor(VOTheme.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
