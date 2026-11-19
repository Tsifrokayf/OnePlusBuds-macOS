import SwiftUI
import AppKit
import AVFoundation

// MARK: - Themes (modelled on the "pop-up themes" of the mobile app)
enum PopupTheme: String, CaseIterable, Identifiable {
    case glass, aurora, neon, island, minimal, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .glass: return tr("Glass")
        case .aurora: return tr("Aurora")
        case .neon: return tr("Neon")
        case .island: return tr("Island")
        case .minimal: return tr("Minimal")
        case .custom: return tr("Custom")
        }
    }
}

struct PopupStyle {
    var theme: PopupTheme
    var glass: Bool
    var customPath: String
    var blur: Double
    var showBattery: Bool
}

enum PopupKind {
    case none
    case connected(String)
    case disconnected(String)
    case info(icon: String, text: String)
    case volume(level: Float, muted: Bool)
}

final class PopupState: ObservableObject {
    @Published var visible = false
    @Published var kind: PopupKind = .none
    @Published var theme: PopupTheme = .glass
    @Published var serial = 0
}

// MARK: - Controller
final class PopupController {
    private unowned let model: AppModel
    private var panel: NSPanel?
    private let state = PopupState()
    private var hideWork: DispatchWorkItem?
    private(set) var lastShown = Date.distantPast
    static let size = CGSize(width: 500, height: 150)

    init(model: AppModel) { self.model = model }

    private func ensurePanel() -> NSPanel {
        if let p = panel { return p }
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: PopupHost(state: state).environmentObject(model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.size)
        p.contentView = host
        panel = p
        return p
    }

    func show(_ kind: PopupKind, theme: PopupTheme? = nil, duration: TimeInterval = 5, force: Bool = false, refresh: Bool = false) {
        guard model.showPopup || force else { return }
        let prevShown = lastShown
        lastShown = Date()
        let sameFamily: Bool = {
            switch (state.kind, kind) {
            case (.volume, .volume), (.info, .info), (.info, .volume), (.volume, .info): return true
            default: return false
            }
        }()
        if state.visible, sameFamily, Date().timeIntervalSince(prevShown) < 2.5 {
            // A HUD is already on screen: morph it, no new entrance animation.
            state.kind = kind
            hideWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
            return
        }
        let p = ensurePanel()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            p.setFrame(NSRect(x: f.midX - Self.size.width / 2, y: f.maxY - Self.size.height,
                              width: Self.size.width, height: Self.size.height), display: false)
        }
        hideWork?.cancel()
        state.kind = kind
        state.theme = theme ?? model.popupTheme
        state.serial += 1
        p.orderFrontRegardless()
        // Show right away: no async hop between ordering the panel front and starting the animation.
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { state.visible = true }
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: w)
    }

    func hide() {
        withAnimation(.easeIn(duration: 0.3)) { state.visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, !self.state.visible else { return }
            self.panel?.orderOut(nil)
        }
    }
}

struct PopupHost: View {
    @ObservedObject var state: PopupState
    @EnvironmentObject var m: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            if state.visible {
                content
                    .id(state.serial)
                    .padding(.top, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .scale(scale: 0.6, anchor: .top)).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)))
            }
        }
        .frame(width: PopupController.size.width, height: PopupController.size.height, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        switch state.kind {
        case .none: EmptyView()
        case .connected(let title): ConnectedPopup(title: title, theme: state.theme)
        case .disconnected(let title): InfoPopup(icon: "xmark.circle", text: trf("%@ Disconnected", title))
        case .info(let icon, let text): InfoPopup(icon: icon, text: text)
        case .volume(let l, let mu): VolumeHUD(level: l, muted: mu)
        }
    }
}

// MARK: - Connected popup (live battery)
struct ConnectedPopup: View {
    @EnvironmentObject var m: AppModel
    let title: String
    let theme: PopupTheme
    @State private var bounce = 0

    private var entries: [Proto.BatteryEntry] {
        if !m.batteryEntries.isEmpty { return m.batteryEntries }
        if !m.cachedBattery.isEmpty { return m.cachedBattery }
        return ["Left", "Right", "Case"].map { Proto.BatteryEntry(name: $0, percent: -1, charging: false) }
    }

    var body: some View {
        ThemedConnectCard(style: m.popupStyle(theme), title: title, entries: entries, bounce: bounce)
            .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bounce += 1 } }
    }
}

/// Pure view — also used for the theme previews in the settings.
struct ThemedConnectCard: View {
    let style: PopupStyle
    let title: String
    let entries: [Proto.BatteryEntry]
    var bounce = 0

    var body: some View {
        switch style.theme {
        case .island: island
        case .minimal: minimal
        default: card
        }
    }

    private var ringTint: Color? { style.theme == .neon ? Color(hex: 0x39FFB6) : nil }

    private var rings: some View {
        HStack(spacing: 12) {
            ForEach(entries, id: \.name) { e in
                RingGauge(label: tr(e.name), percent: e.percent, charging: e.charging, size: 50, tint: ringTint)
            }
        }
        .fixedSize()
    }

    private var content: some View {
        HStack(spacing: 16) {
            Image(systemName: "earbuds")
                .font(.system(size: 32))
                .foregroundColor(style.theme == .neon ? Color(hex: 0x39FFB6) : .white)
                .symbolEffect(.bounce, value: bounce)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    .lineLimit(1).fixedSize()
                Text(tr("Connected")).font(.system(size: 12)).foregroundColor(Color.white.opacity(0.65))
            }
            Spacer(minLength: 6)
            if style.showBattery { rings }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 22).padding(.vertical, 16)
        .frame(width: 460)
    }

    @ViewBuilder private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        switch style.theme {
        case .glass:
            content.glassSurface(shape, glass: style.glass, fallback: Color(hex: 0x1E2128))
        case .aurora:
            content.background(MiniAurora().clipShape(shape))
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        case .neon:
            content.background(shape.fill(Color.black))
                .overlay(shape.stroke(LinearGradient(colors: [Color(hex: 0x39FFB6), Color(hex: 0x4C77F0), Color(hex: 0xC04CF0)],
                                                     startPoint: .leading, endPoint: .trailing), lineWidth: 2))
                .shadow(color: Color(hex: 0x39FFB6).opacity(0.45), radius: 16)
        case .custom:
            content.background(MediaBackground(path: style.customPath, blur: style.blur).clipShape(shape))
                .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 1))
        default:
            content
        }
    }

    private var island: some View {
        HStack(spacing: 12) {
            Image(systemName: "earbuds").font(.system(size: 20)).symbolEffect(.bounce, value: bounce)
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            Spacer(minLength: 10)
            if style.showBattery {
                ForEach(entries, id: \.name) { e in
                    HStack(spacing: 3) {
                        Text(String(tr(e.name).prefix(1))).foregroundColor(Color.white.opacity(0.55))
                        Text(e.percent < 0 ? "–" : "\(e.percent)")
                            .foregroundColor(e.charging || e.percent >= 20 ? Color.charge : .red)
                            .contentTransition(.numericText())
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 22).padding(.vertical, 14)
        .frame(width: 380)
        .background(Capsule().fill(Color.black))
    }

    private var minimal: some View {
        HStack(spacing: 10) {
            Image(systemName: "earbuds").symbolEffect(.bounce, value: bounce)
            if style.showBattery {
                Text(entries.map { "\(String(tr($0.name).prefix(1))) \($0.percent < 0 ? "–" : "\($0.percent)")" }
                        .joined(separator: "  ·  "))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            } else {
                Text(title).font(.system(size: 13, weight: .semibold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .glassSurface(Capsule(), glass: style.glass, fallback: Color(hex: 0x1E2128))
    }
}

struct MiniAurora: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Color(hex: 0x0B0D12)
                Circle().fill(Color.accent.opacity(0.7)).frame(width: 190)
                    .offset(x: CGFloat(sin(t * 0.8)) * 90 - 90, y: CGFloat(cos(t * 0.6)) * 20)
                Circle().fill(Color(hex: 0x8A4CF0).opacity(0.6)).frame(width: 170)
                    .offset(x: CGFloat(cos(t * 0.7)) * 90 + 110, y: CGFloat(sin(t * 0.9)) * 20)
                Circle().fill(Color(hex: 0x23C6B4).opacity(0.5)).frame(width: 140)
                    .offset(x: CGFloat(sin(t * 0.5)) * 60, y: CGFloat(cos(t * 0.5)) * 30 + 40)
            }
            .blur(radius: 38)
        }
    }
}

// MARK: - Custom image / video background
struct MediaBackground: View {
    let path: String
    let blur: Double

    private var isVideo: Bool {
        ["mp4", "mov", "m4v"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    var body: some View {
        ZStack {
            Color.black
            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                if isVideo {
                    VideoBackground(url: URL(fileURLWithPath: path)).blur(radius: blur)
                } else if let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img).resizable().scaledToFill().blur(radius: blur)
                }
            } else {
                LinearGradient(colors: [Color(hex: 0x2E3A63), Color(hex: 0x15171C)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Color.black.opacity(0.3)
        }
    }
}

struct VideoBackground: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> LoopingPlayerView { LoopingPlayerView(url: url) }
    func updateNSView(_ nsView: LoopingPlayerView, context: Context) {}
}

final class LoopingPlayerView: NSView {
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    init(url: URL) {
        super.init(frame: .zero)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer = layer
        wantsLayer = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.isMuted = true
        player.play()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { player.pause() }
}

// MARK: - Short info HUD
struct InfoPopup: View {
    @EnvironmentObject var m: AppModel
    let icon: String
    let text: String
    @State private var pulse = 0

    /// Each kind of action gets its own icon animation.
    @ViewBuilder private var glyph: some View {
        let img = Image(systemName: icon).font(.system(size: 22)).foregroundColor(.white)
        if icon.hasPrefix("play") {
            img.symbolEffect(.bounce.up, value: pulse)
        } else if icon.hasPrefix("pause") {
            img.symbolEffect(.bounce.down, value: pulse)
        } else if icon.contains("waveform") || icon == "sparkles" {
            img.symbolEffect(.variableColor.iterative, options: .repeat(2), isActive: pulse > 0)
        } else if icon.hasPrefix("hand") {
            img.symbolEffect(.pulse, options: .repeat(2), isActive: pulse > 0)
        } else {
            img.symbolEffect(.bounce, value: pulse)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            glyph
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                .lineLimit(1).frame(maxWidth: 360)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .glassSurface(Capsule(), glass: m.liquidGlass, fallback: Color(hex: 0x1E2128))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { pulse += 1 } }
    }
}


// MARK: - Volume HUD (earbud volume buttons)
struct VolumeHUD: View {
    @EnvironmentObject var m: AppModel
    let level: Float
    let muted: Bool

    private var icon: String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        return level < 0.34 ? "speaker.wave.1.fill" : (level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(.white)
                .frame(width: 30)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: max(6, g.size.width * CGFloat(muted ? 0 : level)))
                }
            }
            .frame(width: 170, height: 6)
            Text("\(Int((level * 100).rounded()))").font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundColor(.white).frame(width: 30, alignment: .trailing)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
        .padding(.horizontal, 22).padding(.vertical, 14)
        .glassSurface(Capsule(), glass: m.liquidGlass, fallback: Color(hex: 0x1E2128))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }
}
