// SPDX-License-Identifier: GPL-3.0-or-later
// Ported from VoiceOS Clone (UI/Components.swift) into Vorssaint + VoiceOS.

import SwiftUI
import AppKit

struct VOVisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Dark rounded card used on every settings page.
struct VOCard<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(VOTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }
}

struct VOCardHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundColor(.white)
                if let subtitle {
                    Text(subtitle).font(.system(size: 13)).foregroundColor(VOTheme.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension VOCardHeader where Trailing == EmptyView {
    init(symbol: String, title: String, subtitle: String? = nil) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// The capsule segmented control ("Slow · Normal · Fast").
struct VOSegmentedPill<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let selected = value == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: compact ? 12 : 13, weight: selected ? .semibold : .medium))
                        .foregroundColor(selected ? .white : VOTheme.secondary)
                        .padding(.horizontal, compact ? 11 : 14)
                        .padding(.vertical, compact ? 6 : 8)
                        .background(Capsule().fill(selected ? Color.white.opacity(0.14) : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay(Capsule().stroke(VOTheme.border, lineWidth: 1))
    }
}

struct VOToggleStyle: ToggleStyle {
    var onColor: Color = VOTheme.green
    var knobOn: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? onColor : Color.white.opacity(0.16)).frame(width: 46, height: 28)
                Circle().fill(configuration.isOn ? knobOn : Color.white.opacity(0.85))
                    .frame(width: 23, height: 23)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(2.5)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
            }
        }
    }
}

struct VOToggle: View {
    @Binding var isOn: Bool
    var onColor: Color = VOTheme.green
    var knob: Color = .white
    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(VOToggleStyle(onColor: onColor, knobOn: knob))
    }
}

struct VODarkField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(VOTheme.tertiary))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(VOTheme.tertiary))
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(VOTheme.field))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }
}

/// A little keyboard key ("fn", "command").
struct VOKeyCap: View {
    let label: String
    var dark = true
    var size: CGFloat = 12

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .semibold))
            .foregroundColor(dark ? .white.opacity(0.9) : .black.opacity(0.8))
            .padding(.horizontal, size * 0.65)
            .padding(.vertical, size * 0.25)
            .background(RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                .fill(dark ? Color.white.opacity(0.14) : Color.white))
            .overlay(RoundedRectangle(cornerRadius: size * 0.5, style: .continuous)
                .stroke(Color.white.opacity(dark ? 0.2 : 0), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
    }
}

struct VOStatTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.07)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundColor(VOTheme.secondary).lineLimit(1)
                Text(value).font(.system(size: 20, weight: .semibold)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VOTheme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }
}

struct VOUsageBar: View {
    var fraction: Double
    var color: Color = .white
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                if fraction > 0 {
                    Capsule().fill(color).frame(width: max(height, g.size.width * CGFloat(min(1, fraction))))
                }
            }
        }
        .frame(height: height)
    }
}

/// A real app icon from disk when available, otherwise an SF Symbol tile.
struct VOAppIconView: View {
    var bundleID: String?
    var symbol: String = "app.fill"
    var size: CGFloat = 36
    var image: NSImage?

    var body: some View {
        if let img = image ?? VOAppIcons.icon(bundleID: bundleID) {
            Image(nsImage: img).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x3A3A40), Color(hex: 0x26262A)], startPoint: .top, endPoint: .bottom)))
        }
    }
}

struct VOPrimaryButtonStyle: ButtonStyle {
    var blue = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundColor(blue ? .white : .black)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(blue ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x5B8BFF), VOTheme.accentDeep], startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color.white)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct VOSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

struct VOStatusDot: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8).shadow(color: color.opacity(0.6), radius: 3)
    }
}

/// Renders a small subset of Markdown (paragraphs, bullets, numbered lists, headings, inline styles).
struct VOMarkdownText: View {
    let text: String
    var size: CGFloat = 14
    var color: Color = .white.opacity(0.88)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let s):
                    inline(s).font(.system(size: size + 1, weight: .semibold)).foregroundColor(.white).padding(.top, 2)
                case .bullet(let marker, let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).font(.system(size: size, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                        inline(s).font(.system(size: size)).foregroundColor(color)
                    }
                case .code(let s):
                    Text(s).font(.system(size: size - 1, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                case .paragraph(let s):
                    inline(s).font(.system(size: size)).foregroundColor(color)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private enum Block { case heading(String), bullet(String, String), code(String), paragraph(String) }

    private var blocks: [Block] {
        var out: [Block] = []
        var inCode = false
        var code: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if inCode { out.append(.code(code.joined(separator: "\n"))); code = [] }
                inCode.toggle()
                continue
            }
            if inCode { code.append(raw); continue }
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                out.append(.heading(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
                out.append(.bullet("•", String(line.dropFirst(2))))
            } else if let r = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                out.append(.bullet(String(line[r]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...])))
            } else {
                out.append(.paragraph(line))
            }
        }
        if inCode && !code.isEmpty { out.append(.code(code.joined(separator: "\n"))) }
        return out
    }

    private func inline(_ s: String) -> Text {
        if let a = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(a)
        }
        return Text(s)
    }
}

/// Dark dropdown that opens a popover list (native Menu/Picker can't take this styling on macOS).
struct VODropdown<Value: Hashable, Label: View>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var onPick: ((Value) -> Void)? = nil
    @ViewBuilder var label: Label
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(options.indices, id: \.self) { i in
                            let (value, title) = options[i]
                            Button {
                                selection = value
                                onPick?(value)
                                open = false
                            } label: {
                                HStack(spacing: 10) {
                                    Text(title).font(.system(size: 13.5)).foregroundColor(.white)
                                    Spacer(minLength: 16)
                                    if value == selection {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(VOTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(VODropdownRowStyle())
                        }
                    }
                    .padding(6)
                }
                .frame(minWidth: 240, maxHeight: 360)
                .fixedSize(horizontal: true, vertical: options.count <= 10)
                .preferredColorScheme(.dark)
            }
    }
}

extension VODropdown where Label == VODropdownField {
    init(options: [(Value, String)], selection: Binding<Value>, width: CGFloat = 240, onPick: ((Value) -> Void)? = nil) {
        self.options = options
        self._selection = selection
        self.onPick = onPick
        let title = options.first { $0.0 == selection.wrappedValue }?.1 ?? "Choose…"
        self.label = VODropdownField(title: title, width: width)
    }
}

struct VODropdownField: View {
    let title: String
    var width: CGFloat = 240
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13.5)).foregroundColor(.white).lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundColor(VOTheme.secondary)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(VOTheme.field))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(VOTheme.border, lineWidth: 1))
    }
}

struct VODropdownRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(configuration.isPressed ? VOTheme.accent.opacity(0.35) : Color.clear))
            .modifier(VOHoverHighlight())
    }
}

struct VOHoverHighlight: ViewModifier {
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover ? Color.white.opacity(0.08) : .clear))
            .onHover { hover = $0 }
    }
}
