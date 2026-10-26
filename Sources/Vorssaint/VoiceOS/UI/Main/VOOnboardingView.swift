// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Main/OnboardingView.swift) into Vorssaint + VoiceOS.

import SwiftUI

struct VOOnboardingView: View {
    @ObservedObject private var settings = VOSettings.shared
    @ObservedObject private var perms = VOPermissions.shared
    @ObservedObject private var providers = VOProviderManager.shared
    @State private var step = 0
    @State private var tryText = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x8EC5FF), Color(hex: 0x3F86E0), Color(hex: 0x1B3F8F)], startPoint: .top, endPoint: .bottom)
            // soft clouds
            GeometryReader { g in
                ZStack {
                    Ellipse().fill(.white.opacity(0.55)).frame(width: g.size.width * 0.6, height: 160).blur(radius: 50).offset(x: -g.size.width * 0.25, y: g.size.height * 0.32)
                    Ellipse().fill(.white.opacity(0.45)).frame(width: g.size.width * 0.5, height: 140).blur(radius: 50).offset(x: g.size.width * 0.3, y: g.size.height * 0.4)
                    Ellipse().fill(.white.opacity(0.3)).frame(width: g.size.width * 0.4, height: 100).blur(radius: 40).offset(x: g.size.width * 0.2, y: -g.size.height * 0.3)
                }
                .frame(width: g.size.width, height: g.size.height)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                card
                    .frame(width: 600)
                    .id(step)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                Spacer(minLength: 20)
                dots.padding(.bottom, 34)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: step)
        .onAppear {
            perms.startPolling()
            providers.refreshAll()
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color.white.opacity(i == step ? 0.95 : 0.4)).frame(width: i == step ? 22 : 7, height: 7)
            }
        }
    }

    @ViewBuilder private var card: some View {
        VStack(spacing: 22) {
            switch step {
            case 0: welcome
            case 1: permissions
            case 2: connect
            case 3: aboutYou
            default: tryIt
            }
        }
        .padding(36)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(hex: 0x141416).opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
    }

    private func nav(_ title: String = "Continue", enabled: Bool = true, skip: Bool = false) -> some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(VOSecondaryButtonStyle())
            }
            Spacer()
            if skip {
                Button("Skip for now") { step += 1 }.buttonStyle(.plain).foregroundColor(VOTheme.secondary).font(.system(size: 13))
            }
            Button(title) {
                if step >= 4 { settings.onboardingDone = true } else { step += 1 }
            }
            .buttonStyle(VOPrimaryButtonStyle())
            .disabled(!enabled)
        }
        .padding(.top, 6)
    }

    private var welcome: some View {
        VStack(spacing: 22) {
            VOOrb(size: 110).padding(.top, 10)
            VoiceOSWordmark(height: 44)
            Text("Voice assistant at your fingertips").font(.system(size: 22, weight: .semibold))
            Text("Dictate anywhere, edit by voice, and ask an assistant that can see your screen and act in your apps — running on this Mac with the AI plans you already have.")
                .font(.system(size: 14)).foregroundColor(VOTheme.secondary).multilineTextAlignment(.center)
            Button("Get started") { step = 1 }.buttonStyle(VOPrimaryButtonStyle()).padding(.top, 6)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Give VoiceOS a voice", "macOS asks you to allow each of these once.")
            permRow("mic.fill", "Microphone", "So VoiceOS can hear you.", perms.microphone) { perms.requestMicrophone() }
            permRow("waveform", "Speech Recognition", "On-device transcription — nothing is uploaded.", perms.speech) { perms.requestSpeech() }
            permRow("accessibility", "Accessibility", "To notice fn / ⌘ and type text into your apps.", perms.accessibility) { perms.requestAccessibility() }
            permRow("rectangle.dashed.badge.record", "Screen Recording (optional)", "Lets the assistant see what you're pointing at.", perms.screen) { perms.requestScreen() }
            HStack(spacing: 10) {
                Image(systemName: "globe").foregroundColor(VOTheme.secondary)
                Text("Tip: in Keyboard settings set “Press 🌐 key to” → Do Nothing, so fn is free for dictation.")
                    .font(.system(size: 12)).foregroundColor(VOTheme.secondary)
                Spacer()
                Button("Open") { VOSystemSettings.openKeyboard() }.buttonStyle(VOSecondaryButtonStyle())
            }
            nav(enabled: true, skip: !(perms.microphone && perms.accessibility))
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Connect your AI", "VoiceOS runs on a free local model. Optionally connect Claude, ChatGPT or Gemini for the occasional hard request — it uses the plan you already pay for.")
            ForEach(VOProviderID.allCases) { p in
                let st = providers.status[p] ?? .unknown
                HStack(spacing: 14) {
                    VOProviderLogo(provider: p, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.displayName).font(.system(size: 15, weight: .semibold))
                        HStack(spacing: 6) {
                            VOStatusDot(color: st.color)
                            Text(st.label).font(.system(size: 12)).foregroundColor(VOTheme.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    if settings.agentProvider == p {
                        Text("Default").font(.system(size: 11, weight: .semibold)).foregroundColor(VOTheme.accent)
                    } else {
                        Button("Make default") { settings.agentProvider = p; if settings.polishEngine != .local { settings.polishEngine = VOPolishEngine(rawValue: p.rawValue) ?? .ollama } }
                            .buttonStyle(.plain).font(.system(size: 12)).foregroundColor(VOTheme.secondary)
                    }
                    Button(st.isReady ? "Test" : (p.isLocal ? (VOLocalModels.isInstalled ? "Set up" : "Get Ollama") : "Sign in")) { st.isReady ? providers.test(p) : providers.signIn(p) }
                        .buttonStyle(VOSecondaryButtonStyle())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
                if let t = providers.tests[p] {
                    Text(t.ok ? "✓ \(p.displayName) answered in \(String(format: "%.1f", locale: .current, t.seconds))s" : t.message)
                        .font(.system(size: 12)).foregroundColor(t.ok ? VOTheme.green : VOTheme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Button("Re-check sign-in") { providers.refreshAll() }.buttonStyle(.plain).font(.system(size: 12.5)).foregroundColor(VOTheme.accent)
                Spacer()
            }
            nav(skip: true)
        }
    }

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("What should VoiceOS call you?", "Used for greetings and to sign off emails you dictate.")
            HStack(spacing: 12) {
                VODarkField(placeholder: "First name", text: $settings.firstName)
                VODarkField(placeholder: "Last name", text: $settings.lastName)
            }
            nav()
        }
    }

    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Press").font(.system(size: 24, weight: .bold))
                VOKeyCap(label: settings.dictationTrigger == .fn ? "fn" : settings.dictationTrigger.label, size: 18)
                Text("and start speaking.").font(.system(size: 24, weight: .bold))
            }
            Text("Click in the box, hold the key, say something, and let go.").font(.system(size: 14)).foregroundColor(VOTheme.secondary)
            TextEditor(text: $tryText)
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 14).fill(VOTheme.field))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(VOTheme.border, lineWidth: 1))
            HStack(spacing: 8) {
                Text("Then hold").foregroundColor(VOTheme.secondary)
                VOKeyCap(label: settings.agentTrigger.keycap)
                Text("(\(settings.agentTrigger.label)) to ask the assistant anything.").foregroundColor(VOTheme.secondary)
            }
            .font(.system(size: 13.5))
            nav("Finish")
        }
    }

    private func title(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t).font(.system(size: 22, weight: .bold))
            Text(s).font(.system(size: 13.5)).foregroundColor(VOTheme.secondary)
        }
        .padding(.bottom, 4)
    }

    private func permRow(_ symbol: String, _ name: String, _ desc: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 15)).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14.5, weight: .semibold))
                Text(desc).font(.system(size: 12.5)).foregroundColor(VOTheme.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .medium)).foregroundColor(VOTheme.green)
            } else {
                Button("Allow", action: action).buttonStyle(VOPrimaryButtonStyle())
            }
        }
    }
}
