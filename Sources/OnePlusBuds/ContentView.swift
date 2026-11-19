import SwiftUI

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                noiseCard
                eqCard
                bassCard
                customEqCard
                if !m.isPro3 { gestureCard }
                popupCard
                Text(m.status)
                    .font(.system(size: 11))
                    .foregroundColor(.textLo)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Group { if m.liquidGlass { AuroraBackground() } else { Color.bg } }.ignoresSafeArea())
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: m.noiseSel)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: m.bassOn)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 560)
        .preferredColorScheme(.dark)
    }

    // MARK: Header
    private var header: some View {
        Card(title: m.title) {
            HStack(spacing: 8) {
                if m.devices.isEmpty {
                    TextField(tr("Bluetooth MAC (AA:BB:CC:DD:EE:FF)"), text: $m.manualMac)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: $m.selectedMac) {
                        ForEach(m.devices) { Text($0.name).tag($0.mac) }
                    }
                    .labelsHidden()
                    .onChange(of: m.selectedMac) { _ in m.updateProfile() }
                }
                Button { m.loadDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .help(tr("Refresh paired devices"))
                Button(m.ready ? tr("Reconnect") : tr("Connect")) { m.connect() }
                    .disabled(m.connecting)
                    .keyboardShortcut(.defaultAction)
            }
            HStack {
                EarbudIndicator()
                batteryView
                Spacer()
                Text(m.wornText).font(.system(size: 12)).foregroundColor(.textLo)
                    .animation(.easeInOut, value: m.wornText)
            }
            HStack(spacing: 14) {
                Toggle(tr("Liquid Glass"), isOn: $m.liquidGlass).toggleStyle(.checkbox).font(.system(size: 11))
                Toggle(tr("Start at login"), isOn: Binding(get: { m.startAtLogin }, set: { m.setStartAtLogin($0) }))
                    .toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Button(tr("Packet log")) { openWindow(id: "log") }
                    .buttonStyle(.link).font(.system(size: 11))
            }
            HStack(spacing: 8) {
                Text(tr("Language")).font(.system(size: 11)).foregroundColor(.textLo)
                Picker("", selection: $m.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 190)
                Spacer()
            }
        }
    }

    private var batteryView: some View {
        HStack(spacing: 10) {
            Text(tr("Battery")).foregroundColor(.textLo)
            if m.batteryEntries.isEmpty {
                Text("—").foregroundColor(.textLo)
            } else {
                ForEach(m.batteryEntries, id: \.name) { e in
                    HStack(spacing: 2) {
                        Text("\(tr(e.name)): \(e.percent)%").foregroundColor(.textHi)
                            .contentTransition(.numericText())
                        if e.charging { Text("⚡").foregroundColor(.charge) }
                    }
                }
            }
        }
        .font(.system(size: 12.5))
        .animation(.easeInOut, value: m.batteryEntries)
    }

    // MARK: Noise control
    private func noiseState(_ s: NoiseSel) -> PillState {
        if s == .off && m.anyInEar == false { return .auto }
        return m.noiseSel == s ? .selected : .normal
    }
    private func levelState(_ l: String) -> PillState {
        if m.levelSel == l && m.noiseSel == .anc { return .selected }
        if m.autoSub == l && m.levelSel == "Auto" { return .sub }
        return .normal
    }

    private var noiseCard: some View {
        Card(title: tr("Noise control")) {
            HStack(spacing: 6) {
                PillButton(title: m.isPro3 ? tr("ANC") : tr("Noise Cancellation"), state: noiseState(.anc), enabled: m.ancEnabled) { m.setAnc() }
                if !m.isPro3 {
                    PillButton(title: tr("Adaptive"), state: noiseState(.adaptive), enabled: m.ancEnabled) { m.setAdaptive() }
                }
                PillButton(title: tr("Transparency"), state: noiseState(.trans), enabled: m.ancEnabled) { m.setTransparency() }
                PillButton(title: tr("Off"), state: noiseState(.off), enabled: m.ancEnabled) { m.setOff() }
            }
            if m.isPro3 || m.noiseSel == .anc {
                HStack(spacing: 6) {
                    ForEach(["High", "Moderate", "Low", "Auto"], id: \.self) { l in
                        PillButton(title: (m.isPro3 && l == "Moderate") ? tr("Mid") : tr(l),
                                   state: levelState(l), enabled: m.ancEnabled) { m.setLevel(l) }
                    }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if m.anyInEar == false {
                Text(tr("Put the earbuds in your ears to change noise control"))
                    .font(.system(size: 11)).foregroundColor(.textLo)
            }
        }
    }

    // MARK: Sound master EQ
    private var eqCard: some View {
        Card(title: tr("Sound Master EQ")) {
            HStack(spacing: 6) {
                ForEach(m.eqPresets) { p in
                    PillButton(title: tr(p.label), state: m.eqPreset == p.id ? .selected : .normal, enabled: m.ready) { m.setEq(p) }
                }
            }
        }
    }

    // MARK: BassWave
    private var bassCard: some View {
        Card(title: tr("BassWave™")) {
            Toggle(tr("Enabled"), isOn: Binding(get: { m.bassOn }, set: { m.setBassOn($0) }))
                .disabled(!m.ready)
            if m.bassOn {
                HStack {
                    Slider(value: $m.bassValue, in: -5...5, step: 1) { editing in
                        if !editing { m.commitBassValue() }
                    }
                    Text("\(Int(m.bassValue) > 0 ? "+" : "")\(Int(m.bassValue))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accent)
                        .frame(width: 30, alignment: .trailing)
                }
                .disabled(!m.ready)
            }
        }
    }

    // MARK: Custom EQ
    private var customEqCard: some View {
        Card(title: tr("Custom EQ")) {
            ForEach(0..<6, id: \.self) { i in
                HStack {
                    let hz = Proto.eqBands[i]
                    Text(hz >= 1000 ? "\(hz / 1000)k" : "\(hz)")
                        .font(.system(size: 12)).foregroundColor(.textLo)
                        .frame(width: 40, alignment: .leading)
                    Slider(value: $m.bands[i], in: -6...6, step: 1)
                    let v = Int(m.bands[i])
                    Text("\(v > 0 ? "+" : "")\(v)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.accent)
                        .frame(width: 30, alignment: .trailing)
                }
            }
            HStack {
                TextField(tr("Name"), text: $m.eqName).textFieldStyle(.roundedBorder)
                Button(tr("Create")) { m.createCustomEq() }.disabled(!m.ready)
            }
            HStack {
                Picker("", selection: Binding(get: { m.selectedSlot ?? 0 }, set: { m.selectSlot($0) })) {
                    ForEach(m.customSlots, id: \.id) { Text("\($0.name)\($0.isSelected ? " ✓" : "")").tag($0.id) }
                }
                .labelsHidden()
                .disabled(m.customSlots.isEmpty)
                Button(tr("Select")) { m.selectCustomEq() }.disabled(!m.ready || m.customSlots.isEmpty)
                Button(tr("Delete")) { m.deleteCustomEq() }.disabled(!m.ready || m.customSlots.isEmpty)
            }
        }
    }

    // MARK: Gestures
    private func gesturePicker(_ label: String, _ items: [ActionItem], cat: UInt8, gid: UInt8, def: UInt8) -> some View {
        HStack {
            Text(tr(label)).font(.system(size: 12.5)).foregroundColor(.textHi)
            Spacer()
            Picker("", selection: Binding(
                get: { m.gestureAction(cat: cat, gid: gid, def: def) },
                set: { id in
                    if let item = items.first(where: { $0.id == id }) { m.setGesture(cat: cat, gid: gid, name: tr(label), item: item) }
                })) {
                ForEach(items) { Text(tr($0.label)).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 180)
            .disabled(!m.ready)
        }
    }

    private var gestureCard: some View {
        Card(title: tr("Earbud controls")) {
            HStack(spacing: 6) {
                PillButton(title: tr("Left"), state: m.gestureSide == 1 ? .selected : .normal) { m.gestureSide = 1 }
                PillButton(title: tr("Right"), state: m.gestureSide == 2 ? .selected : .normal) { m.gestureSide = 2 }
            }
            gesturePicker("Single-tap", AppModel.singleTap, cat: 1, gid: 1, def: 0x01)
            gesturePicker("Double-tap", AppModel.doubleTap, cat: 1, gid: 2, def: 0x06)
            gesturePicker("Triple-tap", AppModel.tripleTap, cat: 1, gid: 3, def: m.gestureSide == 1 ? 0x03 : 0x05)
            gesturePicker("Slide", AppModel.slide, cat: 1, gid: 4, def: 0x08)
            gesturePicker("Touch & hold", AppModel.touchHold, cat: 1, gid: 5, def: 0x07)
            Divider()
            Text(tr("During a call")).font(.system(size: 11)).foregroundColor(.textLo)
            gesturePicker("Double-tap", AppModel.callDouble, cat: 6, gid: 2, def: 0x1D)
            gesturePicker("Touch & hold", AppModel.callHold, cat: 6, gid: 6, def: 0x1C)
        }
    }

    // MARK: Connection popup themes (like the pop-up themes in the mobile app)
    private var popupCard: some View {
        Card(title: tr("Connection popup")) {
            Toggle(tr("Connect popup"), isOn: $m.showPopup)
            Toggle(tr("Show battery"), isOn: $m.popupShowBattery)
            Toggle(tr("Earbud action HUD"), isOn: $m.earbudHUD)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                ForEach(PopupTheme.allCases) { t in themeTile(t) }
            }
            if m.popupTheme == .custom || (m.carouselOn && m.carouselThemes.contains("custom")) {
                HStack {
                    Button(tr("Choose image or video…")) { m.chooseMedia() }
                    Spacer()
                    Text(tr("Blur")).font(.system(size: 11)).foregroundColor(.textLo)
                    Slider(value: $m.customBlur, in: 0...30).frame(width: 110)
                }
            }
            Toggle(tr("Theme carousel"), isOn: $m.carouselOn)
            if m.carouselOn {
                HStack {
                    Text(tr("Rotation")).font(.system(size: 11)).foregroundColor(.textLo)
                    Picker("", selection: $m.carouselFreq) {
                        Text(tr("Every connection")).tag("connection")
                        Text(tr("Every day")).tag("day")
                        Text(tr("Every week")).tag("week")
                    }
                    .labelsHidden()
                }
                if m.carouselThemes.count < 2 {
                    Text(tr("Pick at least 2 themes for the carousel"))
                        .font(.system(size: 11)).foregroundColor(.autoOff)
                }
            }
            HStack {
                Spacer()
                Button(tr("Preview")) { m.previewPopup() }
            }
        }
    }

    private func themeTile(_ t: PopupTheme) -> some View {
        let selected = m.carouselOn ? m.carouselThemes.contains(t.rawValue) : m.popupTheme == t
        return Button { m.tapTheme(t) } label: {
            VStack(spacing: 6) {
                ThemedConnectCard(style: m.popupStyle(t), title: "OnePlus Buds", entries: [
                    Proto.BatteryEntry(name: "Left", percent: 80, charging: false),
                    Proto.BatteryEntry(name: "Right", percent: 80, charging: false),
                    Proto.BatteryEntry(name: "Case", percent: 64, charging: true)])
                    .frame(width: t == .island ? 380 : 460, height: 100)
                    .scaleEffect(0.29)
                    .frame(width: 134, height: 34)
                Text(t.title).font(.system(size: 11, weight: .medium)).foregroundColor(.textHi)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accent : Color.clear, lineWidth: 2))
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
