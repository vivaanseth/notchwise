// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/DictationPill.swift) into Vorssaint + VoiceOS.

import AppKit
import SwiftUI
import Combine

/// The black waveform pill at the bottom-center of the screen while dictating.
@MainActor
final class VODictationPillController {
    let panel: NSPanel
    private var bag = Set<AnyCancellable>()

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 80),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: VOPillView())
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        position()
        panel.orderFrontRegardless()

        VODictationController.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .listening || state == .handsFree { self.position() }
                switch state {
                case .handsFree, .message: self.panel.ignoresMouseEvents = false
                default: self.panel.ignoresMouseEvents = true
                }
                self.panel.orderFrontRegardless()
            }
            .store(in: &bag)
    }

    func close() {
        bag.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        panel.setFrame(NSRect(x: v.midX - 280, y: v.minY + 6, width: 560, height: 80), display: true)
    }
}

struct VOPillView: View {
    @ObservedObject private var d = VODictationController.shared
    @ObservedObject private var settings = VOSettings.shared

    var body: some View {
        VStack {
            Spacer()
            content
                .animation(.spring(response: 0.34, dampingFraction: 0.78), value: d.state)
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch d.state {
        case .hidden:
            if settings.showIdlePill {
                Capsule().fill(Color.black.opacity(0.6)).frame(width: 40, height: 7)
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        case .listening:
            pill {
                appIcon
                VOWaveform(level: d.level, bars: 7, height: 16, barWidth: 3)
            }
        case .handsFree:
            pill {
                appIcon
                VOWaveform(level: d.level, bars: 7, height: 16, barWidth: 3)
                Button { endHandsFree(); d.cancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
                Button { endHandsFree(); d.finish() } label: {
                    RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 7, height: 7)
                        .frame(width: 20, height: 20).background(Circle().fill(VOTheme.red))
                }
                .buttonStyle(.plain)
            }
        case .processing:
            pill {
                appIcon
                VOThinkingDots()
                    .frame(width: 40)
            }
        case .done:
            pill {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(VOTheme.green)
            }
        case .message(let text, let isError):
            pill {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "waveform")
                    .foregroundColor(isError ? VOTheme.orange : .white.opacity(0.7))
                    .font(.system(size: 13))
                Text(text).font(.system(size: 12.5, weight: .medium)).foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: 440, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onTapGesture { VOMainWindow.show(.apps) }
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let icon = d.appIcon {
            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
        }
    }

    private func pill<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 9) { c() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Capsule().fill(Color.black))
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .transition(.scale(scale: 0.2).combined(with: .opacity))
    }

    private func endHandsFree() {
        VORuntime.shared.hotkeys.endHandsFree()
    }
}
