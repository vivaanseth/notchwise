// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Notch/NotchView.swift) into Vorssaint + VoiceOS.

import SwiftUI

private struct VOTurnsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - The assistant's page

/// The assistant's page in the open island: VoiceOS's open notch. Its top
/// bar is the island's own row, the Jarvis mark leading it and a new
/// conversation and close ending it; below come the turns and the input row.
/// The island is as tall as the page, as VoiceOS's notch was.
struct VOVoicePage: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var agent = VOAssistantController.shared
    @ObservedObject private var voice = VOAssistantVoice.shared

    var body: some View {
        VOExpandedNotch()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateVoiceHeight($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // VoiceOS's dark blue fade at the island's foot, out to its
            // edges; the island's own outline clips it.
            .background {
                VOVoiceBackdrop()
                    .padding(.horizontal, -NotchLayout.horizontalInset)
                    .padding(.bottom, -NotchLayout.bottomInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .notchBand(leading: {
                VOJarvisGlyph(size: 17, active: agent.phase == .listening || agent.phase == .thinking || voice.speaking)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }, trailing: {
                if !agent.turns.isEmpty {
                    NotchIconButton(symbol: "square.and.pencil", title: "New conversation") {
                        agent.turns.removeAll()
                        agent.phase = .idle
                    }
                }
                NotchIconButton(symbol: "xmark", title: "Close (Esc)") { agent.close() }
            })
    }
}

/// VoiceOS's dark blue fade, behind the assistant's page.
struct VOVoiceBackdrop: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .black.opacity(0.03), location: 0.55),
                               .init(color: Color(hex: 0x0B1730).opacity(0.72), location: 0.9),
                               .init(color: Color(hex: 0x2A4E86).opacity(0.55), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Expanded

private struct VOExpandedNotch: View {
    @ObservedObject private var agent = VOAssistantController.shared
    @ObservedObject private var voice = VOAssistantVoice.shared
    @ObservedObject private var settings = VOSettings.shared
    @FocusState private var focused: Bool
    @State private var turnsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !agent.turns.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(agent.turns) { turn in
                                VOTurnView(turn: turn).id(turn.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.top, 2)
                        .background(GeometryReader { g in Color.clear.preference(key: VOTurnsHeightKey.self, value: g.size.height) })
                    }
                    .frame(height: min(turnsHeight, 470))
                    .onPreferenceChange(VOTurnsHeightKey.self) { turnsHeight = $0 }
                    .onChange(of: agent.turns) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            if let hint = agent.hint {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundColor(.white.opacity(0.6))
                    Text(hint).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 10)
            }
            inputRow.padding(.top, agent.turns.isEmpty ? 2 : 14)
        }
        .padding(.horizontal, 8)
        .onChange(of: agent.focusToken) { _, _ in focused = true }
        .onAppear { if agent.focusToken > 0, VOIsland.isTyping { focused = true } }
    }

    @ViewBuilder private var inputRow: some View {
        HStack(spacing: 12) {
            switch agent.phase {
            case .listening:
                Text(agent.live.isEmpty ? "Listening…" : agent.live)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(agent.live.isEmpty ? .white.opacity(0.5) : .white)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VOWaveform(level: agent.level, bars: 9, height: 22)
            case .transcribing:
                VOShimmerText(text: "Transcribing…", size: 17)
                Spacer()
            default:
                ZStack(alignment: .leading) {
                    if agent.input.isEmpty {
                        HStack(spacing: 7) {
                            Text("Type or hold")
                            VOKeyCap(label: settings.agentTrigger.keycap, size: 12.5)
                            Text("to speak")
                        }
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.42))
                        .allowsHitTesting(false)
                    }
                    TextField("", text: $agent.input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                        .lineLimit(1...4)
                        .focused($focused)
                        .onSubmit { agent.submit(agent.input) }
                }
                if agent.phase == .thinking {
                    VOThinkingDots()
                } else if !agent.input.isEmpty {
                    Button { agent.submit(agent.input) } label: {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundColor(.black)
                            .frame(width: 28, height: 28).background(Circle().fill(Color.white))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .onTapGesture {
            VOIsland.focusInput()
            focused = true
        }
    }
}

private struct VOTurnView: View {
    let turn: VOAssistantTurn
    @ObservedObject private var voice = VOAssistantVoice.shared
    @ObservedObject private var agent = VOAssistantController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(turn.query)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x1E1E20)))
                .textSelection(.enabled)

            if turn.thinking && turn.say.isEmpty {
                HStack(spacing: 10) {
                    VOProviderLogo(provider: turn.provider, size: 16)
                    VOShimmerText(text: turn.usedScreen ? "Looking at your screen…"
                                : (turn.provider.isLocal ? "Thinking on this Mac…" : "Asking \(turn.provider.displayName)…"), size: 15)
                }
                .padding(.leading, 2)
            }
            if !turn.say.isEmpty {
                spoken.padding(.horizontal, 2)
            }
            if let detail = turn.detail {
                VOMarkdownText(text: detail, size: 14.5).padding(.horizontal, 2)
            }
            if let error = turn.error {
                VOErrorCard(message: error, provider: turn.provider)
            }
            ForEach(turn.actions) { item in
                VOActionCardView(turnID: turn.id, item: item)
            }
            if !turn.via.isEmpty && !turn.thinking {
                HStack(spacing: 6) {
                    VOProviderLogo(provider: turn.provider, size: 12)
                    Text(turn.via).font(.system(size: 11)).foregroundColor(.white.opacity(0.38)).lineLimit(1)
                }
                .padding(.leading, 2)
            }
        }
    }

    private var spoken: some View {
        let text = turn.say
        let upTo = voice.currentText == text ? min(voice.spokenUpTo, text.utf16.count) : text.utf16.count
        let idx = String.Index(utf16Offset: upTo, in: text)
        return (Text(text[..<idx]).foregroundColor(.white) + Text(text[idx...]).foregroundColor(.white.opacity(0.4)))
            .font(.system(size: 20, weight: .medium))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

private struct VOErrorCard: View {
    let message: String
    let provider: VOProviderID
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(VOTheme.orange).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 10) {
                Text(message).font(.system(size: 13.5)).foregroundColor(.white.opacity(0.88)).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Fix \(provider.displayName) connection") { VOMainWindow.show(.apps) }
                        .buttonStyle(VOSecondaryButtonStyle())
                    Button("Use another AI") { VOMainWindow.show(.assistant) }
                        .buttonStyle(VOSecondaryButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VOTheme.orange.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VOTheme.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Action cards

struct VOActionCardView: View {
    let turnID: UUID
    let item: VOAssistantActionItem
    @ObservedObject private var agent = VOAssistantController.shared

    private var spec: VOActionSpec { VOActionKit.spec(item.action.type) }

    var body: some View {
        switch item.state {
        case .needsConfirm:
            confirmCard
        case .running:
            statusRow(text: spec.title + "…") { ProgressView().controlSize(.small) }
        case .done(let msg):
            VStack(alignment: .leading, spacing: 8) {
                statusRow(text: msg) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(VOTheme.green).font(.system(size: 16))
                }
                if !item.files.isEmpty { fileList }
            }
        case .failed(let msg):
            statusRow(text: msg, tint: VOTheme.orange) {
                Image(systemName: "exclamationmark.circle.fill").foregroundColor(VOTheme.orange).font(.system(size: 16))
            }
        case .cancelled:
            statusRow(text: "Cancelled", dim: true) { Image(systemName: "xmark.circle").foregroundColor(.white.opacity(0.4)) }
        }
    }

    private func statusRow<T: View>(text: String, tint: Color = .white, dim: Bool = false, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 10) {
            VOAppIconView(bundleID: spec.bundleID, symbol: spec.symbol, size: 20)
            Text(text).font(.system(size: 13.5, weight: .medium)).foregroundColor(dim ? .white.opacity(0.45) : tint.opacity(0.9))
                .lineLimit(2)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.files, id: \.self) { url in
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                            Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 11)).foregroundColor(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Image(systemName: "folder").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var confirmCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VOAppIconView(bundleID: spec.bundleID, symbol: spec.symbol, size: 42)
            VStack(alignment: .leading, spacing: 7) {
                Text(spec.appName).font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                Text(spec.title).font(.system(size: 17, weight: .semibold)).foregroundColor(.white).padding(.bottom, 2)
                ForEach(spec.fields, id: \.key) { field in
                    fieldRow(field.label, key: field.key, multiline: field.multiline)
                }
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                Button(spec.primary) { agent.confirm(turnID: turnID, actionID: item.id) }
                    .buttonStyle(VOCardButtonStyle(primary: true))
                    .keyboardShortcut(.defaultAction)
                if let secondary = spec.secondary {
                    Button(secondary) { agent.confirm(turnID: turnID, actionID: item.id, secondary: true) }
                        .buttonStyle(VOCardButtonStyle(primary: false))
                }
                Button(item.editing ? "Done" : "Edit") { agent.toggleEdit(turnID: turnID, actionID: item.id) }
                    .buttonStyle(VOCardButtonStyle(primary: false))
            }
            .frame(width: 112)
            .padding(.top, 22)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            Button { agent.cancelAction(turnID: turnID, actionID: item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }

    @ViewBuilder
    private func fieldRow(_ label: String, key: String, multiline: Bool) -> some View {
        let value = item.action[key]
        if item.editing {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5))
                TextField(label, text: Binding(get: { item.action[key] },
                                               set: { agent.setField(turnID: turnID, actionID: item.id, key: key, value: $0) }),
                          axis: multiline ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .lineLimit(multiline ? 1...6 : 1...1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.35)))
            }
        } else if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label):").font(.system(size: 13.5)).foregroundColor(.white.opacity(0.55))
                Text(display(key: key, value: value))
                    .font(.system(size: 13.5))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(multiline ? 4 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func display(key: String, value: String) -> String {
        switch key {
        case "start", "due", "end": return VODateParse.parse(value).map(VODateParse.friendly) ?? value
        case "duration_minutes": return "\(value) min"
        default: return value
        }
    }
}

struct VOCardButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(primary ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x6A95FF), Color(hex: 0x3D66F2)], startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(Color.white.opacity(0.14)))
            )
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(primary ? 0.25 : 0.1), lineWidth: 1))
            .shadow(color: primary ? Color(hex: 0x3D66F2).opacity(0.45) : .clear, radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}
