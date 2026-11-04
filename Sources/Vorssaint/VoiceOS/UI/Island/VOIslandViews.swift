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
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchHiddenModules) private var hiddenModules = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The assistant on the home, unless it is off or was removed from the
    /// island. Without it the home keeps its dashboard, looking the same.
    private var assistant: Bool {
        let _ = hiddenModules
        return NotchSupport.showsAssistant()
    }

    /// Before anything is asked, the page is the island's home too: the
    /// day's events, a small mirror, quick controls and the song playing
    /// below the field. Listening or answering, it steps aside for the
    /// conversation.
    private var showsHub: Bool {
        guard assistant else { return true }
        return agent.turns.isEmpty && agent.hint == nil && (agent.phase == .idle || agent.phase == .collapsed)
            && !service.hubModules.isEmpty
    }

    /// Listening, thinking or speaking: the only time the page wears colour.
    private var assistantActive: Bool {
        assistant && (agent.phase == .listening || agent.phase == .thinking || voice.speaking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if assistant {
                VOExpandedNotch()
                    .contextMenu {
                        NotchRemoveButton(item: .page(.voice),
                                          title: FeatureStrings.notchCustomization(l10n.language).removeAssistant)
                    }
            }
            if showsHub {
                NotchHubView(service: service, selection: assistant ? agent.frontSelection : nil) { agent.submit($0) }
                    .padding(.horizontal, 8)
                    .padding(.top, assistant ? 14 : 6)
                    .transition(.blurReplace)
            }
        }
        .animation(reduceMotion ? nil : NotchStyle.Motion.state, value: showsHub)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { service.updateVoiceHeight($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // At rest the home is the island's plain black, as every page is.
        // While the assistant listens, thinks or speaks, VoiceOS's blue rises
        // from the island's foot and settles back after, out to its edges;
        // the island's own outline clips it.
        .background {
            VOVoiceBackdrop()
                .opacity(assistantActive ? 1 : 0)
                .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: assistantActive)
                .padding(.horizontal, -NotchLayout.horizontalInset)
                .padding(.bottom, -NotchLayout.bottomInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .notchBand(leading: {
            if assistant {
                VOJarvisGlyph(size: 17, active: assistantActive)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "house.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchStyle.secondary)
                    .padding(.leading, 6)
                    .accessibilityHidden(true)
            }
            // The island's pages, at the top of its home.
            NotchHubPageBar(service: service)
        }, trailing: {
            if assistant, !agent.turns.isEmpty {
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
                        withAnimation(NotchStyle.Motion.scroll) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            if let hint = agent.hint {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(NotchStyle.secondary)
                    Text(hint).font(NotchStyle.Typeface.body).foregroundStyle(NotchStyle.secondary)
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
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(agent.live.isEmpty ? NotchStyle.secondary : NotchStyle.primary)
                    .contentTransition(.opacity)
                    .animation(NotchStyle.Motion.follow, value: agent.live)
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
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(NotchStyle.tertiary)
                        .allowsHitTesting(false)
                    }
                    TextField("", text: $agent.input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
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
                    .buttonStyle(NotchButtonStyle(cornerRadius: 14, highlights: false))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
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
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NotchStyle.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NotchStyle.control, in: RoundedRectangle(cornerRadius: NotchStyle.Radius.card, style: .continuous))
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
                    Text(turn.via).font(NotchStyle.Typeface.caption).foregroundStyle(NotchStyle.tertiary).lineLimit(1)
                }
                .padding(.leading, 2)
            }
        }
    }

    private var spoken: some View {
        let text = turn.say
        let upTo = voice.currentText == text ? min(voice.spokenUpTo, text.utf16.count) : text.utf16.count
        let idx = String.Index(utf16Offset: upTo, in: text)
        return (Text(text[..<idx]).foregroundColor(NotchStyle.primary) + Text(text[idx...]).foregroundColor(NotchStyle.tertiary))
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
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NotchStyle.Tint.orange).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 10) {
                Text(message).font(NotchStyle.Typeface.body).foregroundStyle(NotchStyle.primary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Fix \(provider.displayName) connection") { VOMainWindow.show(.apps) }
                        .buttonStyle(NotchCapsuleButtonStyle(prominent: true))
                    Button("Use another AI") { VOMainWindow.show(.assistant) }
                        .buttonStyle(NotchCapsuleButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .notchPlatter()
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
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(NotchStyle.Tint.green).font(.system(size: 16))
                }
                if !item.files.isEmpty { fileList }
            }
        case .failed(let msg):
            statusRow(text: msg, tint: NotchStyle.Tint.orange) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(NotchStyle.Tint.orange).font(.system(size: 16))
            }
        case .cancelled:
            statusRow(text: "Cancelled", dim: true) { Image(systemName: "xmark.circle").foregroundStyle(NotchStyle.tertiary) }
        }
    }

    private func statusRow<T: View>(text: String, tint: Color = .white, dim: Bool = false, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 10) {
            VOAppIconView(bundleID: spec.bundleID, symbol: spec.symbol, size: 20)
            Text(text).font(NotchStyle.Typeface.body.weight(.medium)).foregroundStyle(dim ? NotchStyle.tertiary : tint)
                .lineLimit(2)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NotchStyle.platter, in: Capsule())
        .transition(.blurReplace)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(item.files, id: \.self) { url in
                Button { NSWorkspace.shared.open(url) } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent).font(NotchStyle.Typeface.body.weight(.medium)).foregroundStyle(NotchStyle.primary).lineLimit(1)
                            Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                                .font(NotchStyle.Typeface.caption).foregroundStyle(NotchStyle.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                            Image(systemName: "folder").font(.system(size: 11, weight: .medium)).foregroundStyle(NotchStyle.secondary)
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
        .notchPlatter(cornerRadius: NotchStyle.Radius.card)
    }

    private var confirmCard: some View {
        HStack(alignment: .top, spacing: 14) {
            VOAppIconView(bundleID: spec.bundleID, symbol: spec.symbol, size: 42)
            VStack(alignment: .leading, spacing: 7) {
                Text(spec.appName).font(NotchStyle.Typeface.headline).foregroundStyle(NotchStyle.secondary)
                Text(spec.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(NotchStyle.primary).padding(.bottom, 2)
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
        .notchPlatter(cornerRadius: 24)
        .overlay(alignment: .topTrailing) {
            Button { agent.cancelAction(turnID: turnID, actionID: item.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(NotchStyle.secondary)
                    .frame(width: 24, height: 24).background(NotchStyle.control, in: Circle())
            }
            .buttonStyle(NotchButtonStyle(cornerRadius: 12))
            .padding(10)
        }
        .transition(.blurReplace)
    }

    @ViewBuilder
    private func fieldRow(_ label: String, key: String, multiline: Bool) -> some View {
        let value = item.action[key]
        if item.editing {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(NotchStyle.Typeface.caption).foregroundStyle(NotchStyle.secondary)
                TextField(label, text: Binding(get: { item.action[key] },
                                               set: { agent.setField(turnID: turnID, actionID: item.id, key: key, value: $0) }),
                          axis: multiline ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundColor(.white)
                    .lineLimit(multiline ? 1...6 : 1...1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: NotchStyle.Radius.button, style: .continuous))
            }
        } else if !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(label):").font(NotchStyle.Typeface.body).foregroundStyle(NotchStyle.secondary)
                Text(display(key: key, value: value))
                    .font(NotchStyle.Typeface.body)
                    .foregroundStyle(NotchStyle.primary)
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

/// The confirmation card's buttons: the step it asks for in the system's
/// blue, the others on the control fill, all capsules with no glow, as the
/// island's other buttons are.
struct VOCardButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NotchStyle.Typeface.headline)
            .foregroundStyle(NotchStyle.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(primary ? NotchStyle.Tint.blue : NotchStyle.control, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : NotchStyle.Motion.press, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}
