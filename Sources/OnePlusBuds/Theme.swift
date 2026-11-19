import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let bg      = Color(hex: 0x15171C)
    static let card    = Color(hex: 0x1E2128)
    static let pill    = Color(hex: 0x2A2E38)
    static let accent  = Color(hex: 0x4C77F0)
    static let subSel  = Color(hex: 0x2E3A63)
    static let autoOff = Color(hex: 0xD8C24A)
    static let textHi  = Color(hex: 0xE6E8EE)
    static let textLo  = Color(hex: 0x9AA0B0)
    static let charge  = Color(hex: 0x4CC95A)
}

// MARK: - Liquid Glass (macOS 26+), graceful fallback on older systems / when switched off
extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, glass: Bool, tint: Color? = nil,
                                interactive: Bool = false, fallback: Color = Color.card) -> some View {
        #if compiler(>=6.2)
        if glass, #available(macOS 26.0, *) {
            let style: Glass = {
                var g = Glass.regular
                if let t = tint { g = g.tint(t) }
                if interactive { g = g.interactive() }
                return g
            }()
            self.glassEffect(style, in: shape)
        } else {
            self.background(shape.fill(glass ? AnyShapeStyle(Material.ultraThinMaterial) : AnyShapeStyle(fallback)))
        }
        #else
        self.background(shape.fill(glass ? AnyShapeStyle(Material.ultraThinMaterial) : AnyShapeStyle(fallback)))
        #endif
    }
}

/// Soft drifting colour blobs so the glass has something to refract.
struct AuroraBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(hex: 0x0B0D12)
                Circle().fill(Color.accent.opacity(0.55)).frame(width: 340)
                    .offset(x: CGFloat(sin(t * 0.21)) * 120 - 60, y: CGFloat(cos(t * 0.17)) * 160 - 200)
                Circle().fill(Color(hex: 0x8A4CF0).opacity(0.45)).frame(width: 300)
                    .offset(x: CGFloat(cos(t * 0.19)) * 130 + 90, y: CGFloat(sin(t * 0.23)) * 200 + 60)
                Circle().fill(Color(hex: 0x23C6B4).opacity(0.35)).frame(width: 260)
                    .offset(x: CGFloat(sin(t * 0.15)) * 140 - 80, y: CGFloat(cos(t * 0.13)) * 180 + 260)
            }
            .blur(radius: 80)
            .clipped()
        }
    }
}

/// Springy press effect for every button.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

enum PillState { case normal, selected, sub, auto }

struct PillButton: View {
    @EnvironmentObject var m: AppModel
    let title: String
    var state: PillState = .normal
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundColor(fg)
                .glassSurface(RoundedRectangle(cornerRadius: 10), glass: m.liquidGlass,
                              tint: glassTint, interactive: true, fallback: bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(bgColor.opacity(m.liquidGlass && state != .normal ? 0.25 : 0))
                )
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(state == .sub ? Color.accent : Color.clear, lineWidth: 1))
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .animation(.spring(response: 0.38, dampingFraction: 0.62), value: state)
    }

    private var glassTint: Color? {
        switch state {
        case .normal: return nil
        case .selected: return Color.accent.opacity(0.9)
        case .sub: return Color.accent.opacity(0.4)
        case .auto: return Color.autoOff.opacity(0.85)
        }
    }
    private var bgColor: Color {
        switch state {
        case .normal: return .pill
        case .selected: return .accent
        case .sub: return .subSel
        case .auto: return .autoOff
        }
    }
    private var fg: Color {
        switch state {
        case .auto: return Color(hex: 0x15171C)
        case .selected: return .white
        default: return .textHi
        }
    }
}

struct Card<Content: View>: View {
    @EnvironmentObject var m: AppModel
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textLo)
                .tracking(0.8)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(RoundedRectangle(cornerRadius: m.liquidGlass ? 22 : 12), glass: m.liquidGlass)
    }
}

// MARK: - Earbud widgets used in the window, popup and desktop widget
struct RingGauge: View {
    let label: String
    let percent: Int          // < 0 → unknown yet
    let charging: Bool
    var size: CGFloat = 54
    var tint: Color? = nil
    @State private var shown: Double = 0

    private var color: Color {
        if let tint { return tint }
        if charging || percent >= 50 { return .charge }
        return percent >= 20 ? .autoOff : .red
    }
    private var target: Double { percent < 0 ? 0 : Double(percent) / 100 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(percent < 0 ? "–" : "\(percent)")
                        .font(.system(size: size * 0.29, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    if charging {
                        Image(systemName: "bolt.fill").font(.system(size: size * 0.18)).foregroundColor(.charge)
                    }
                }
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))
                .lineLimit(1)
                .fixedSize()
        }
        .onAppear { withAnimation(.easeOut(duration: 0.6).delay(0.05)) { shown = target } }
        .onChange(of: percent) { _ in withAnimation(.easeInOut(duration: 0.6)) { shown = target } }
    }
}

/// Two earbuds that light up with the real touch gestures reported by the hardware.
struct EarbudIndicator: View {
    @EnvironmentObject var m: AppModel
    @State private var flashL = false
    @State private var flashR = false

    var body: some View {
        HStack(spacing: 8) {
            bud("L", flash: flashL)
            bud("R", flash: flashR)
        }
        .onChange(of: m.tapCounter) { _ in
            if m.tapSide != 2 {
                flashL = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flashL = false }
            }
            if m.tapSide != 1 {
                flashR = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flashR = false }
            }
        }
    }

    private func bud(_ t: String, flash: Bool) -> some View {
        ZStack {
            Capsule().fill(m.anyInEar == true ? Color.accent : Color.pill)
                .frame(width: 20, height: 34)
            Text(t).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
        }
        .scaleEffect(flash ? 1.4 : 1)
        .shadow(color: flash ? Color.accent : .clear, radius: flash ? 12 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.42), value: flash)
        .animation(.easeInOut(duration: 0.4), value: m.anyInEar)
        .opacity(m.ready ? 1 : 0.4)
    }
}
