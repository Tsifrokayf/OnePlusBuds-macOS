import Foundation
import IOBluetooth
import ServiceManagement
import UserNotifications
import AppKit
import Combine
import WidgetKit
import UniformTypeIdentifiers

struct BudsDevice: Identifiable, Hashable {
    let name: String
    let mac: String
    var id: String { mac }
}

struct ActionItem: Identifiable, Hashable {
    let id: UInt8
    let label: String
}

struct GestureKey: Hashable { let side: UInt8, cat: UInt8, gid: UInt8 }

enum NoiseSel { case none, anc, adaptive, trans, off }

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

final class AppModel: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    // MARK: Connection state
    @Published var devices: [BudsDevice] = []
    @Published var selectedMac: String = ""
    @Published var manualMac: String = ""
    @Published var status: String = "Select a device and press Connect"
    @Published var ready = false
    @Published var connecting = false
    @Published var isPro3 = false

    // MARK: Device state
    @Published var batteryEntries: [Proto.BatteryEntry] = []
    @Published var bothInCase: Bool? = nil
    @Published var anyInEar: Bool? = nil
    @Published var noiseSel: NoiseSel = .none
    @Published var levelSel: String? = nil      // High / Moderate / Low / Auto
    @Published var autoSub: String? = nil       // level Auto is currently applying
    @Published var eqPreset: UInt8? = nil
    @Published var bassOn = false
    @Published var bassValue: Double = 0
    @Published var customSlots: [Proto.EqEntry] = []
    @Published var selectedSlot: UInt8? = nil
    @Published var bands: [Double] = Array(repeating: 0, count: 6)
    @Published var eqName = ""
    @Published var gestureMap: [GestureKey: UInt8] = [:]
    @Published var gestureSide: UInt8 = 1
    @Published var startAtLogin = false
    static weak var shared: AppModel?
    @Published var liquidGlass = true { didSet { UserDefaults.standard.set(liquidGlass, forKey: "liquidGlass") } }
    @Published var showPopup = true { didSet { UserDefaults.standard.set(showPopup, forKey: "showPopup") } }
    @Published var earbudHUD = true { didSet { UserDefaults.standard.set(earbudHUD, forKey: "earbudHUD") } }
    @Published var popupShowBattery = true { didSet { UserDefaults.standard.set(popupShowBattery, forKey: "popupShowBattery") } }
    @Published var popupTheme: PopupTheme = .glass { didSet { UserDefaults.standard.set(popupTheme.rawValue, forKey: "popupTheme") } }
    @Published var carouselOn = false { didSet { UserDefaults.standard.set(carouselOn, forKey: "carouselOn") } }
    @Published var carouselThemes: [String] = ["glass", "aurora"] { didSet { UserDefaults.standard.set(carouselThemes, forKey: "carouselThemes") } }
    @Published var carouselFreq = "connection" { didSet { UserDefaults.standard.set(carouselFreq, forKey: "carouselFreq") } }
    @Published var customMediaPath = "" { didSet { UserDefaults.standard.set(customMediaPath, forKey: "customMediaPath") } }
    @Published var customBlur = 12.0 { didSet { UserDefaults.standard.set(customBlur, forKey: "customBlur") } }
    @Published var language: AppLanguage = .auto {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language"); Lang.current = language }
    }
    @Published var cachedBattery: [Proto.BatteryEntry] = []
    @Published var tapCounter = 0
    @Published var tapSide: UInt8 = 0
    lazy var popups = PopupController(model: self)
    lazy var activity = ActivityMonitor(model: self)
    private var lastUserCommand = Date.distantPast
    private var connectedAt = Date.distantPast
    private var popupShownSession = false
    private var connectNote: IOBluetoothUserNotification?
    private var cancellables = Set<AnyCancellable>()
    private var lastWidgetKey = Data()
    private var widgetReloadWork: DispatchWorkItem?

    // MARK: Log
    @Published var logLines: [LogLine] = []
    @Published var packetCount = 0
    @Published var autoScroll = true
    private let maxLines = 2000
    private let logFileURL: URL

    // MARK: Internals
    private var channel: IOBluetoothRFCOMMChannel?
    private var rxBuffer: [UInt8] = []
    private var pollTimer: Timer?
    private var reconnectTimer: Timer?
    private var wasConnected = false
    private var batteryNotificationShown = false
    private var lastBatterySummary: String?
    private var ancAuto = false
    private var pendingAck: [UInt8: String] = [:]
    private var lastStateRequest = Date.distantPast
    private var connectToken = 0
    private var lastNotifKey = ""
    private var lastNotifTime = Date.distantPast

    override init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/OnePlusBuds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logFileURL = dir.appendingPathComponent("packet_log.txt")
        super.init()
        startAtLogin = SMAppService.mainApp.status == .enabled
        AppModel.shared = self
        let ud = UserDefaults.standard
        language = AppLanguage(rawValue: ud.string(forKey: "language") ?? "") ?? .auto
        Lang.current = language
        liquidGlass = ud.object(forKey: "liquidGlass") as? Bool ?? true
        showPopup = ud.object(forKey: "showPopup") as? Bool ?? true
        popupShowBattery = ud.object(forKey: "popupShowBattery") as? Bool ?? true
        earbudHUD = ud.object(forKey: "earbudHUD") as? Bool ?? true
        popupTheme = PopupTheme(rawValue: ud.string(forKey: "popupTheme") ?? "") ?? .glass
        carouselOn = ud.bool(forKey: "carouselOn")
        carouselThemes = ud.stringArray(forKey: "carouselThemes") ?? ["glass", "aurora"]
        carouselFreq = ud.string(forKey: "carouselFreq") ?? "connection"
        customMediaPath = ud.string(forKey: "customMediaPath") ?? ""
        customBlur = ud.object(forKey: "customBlur") as? Double ?? 12
        if let data = ud.data(forKey: "cachedBattery"),
           let arr = try? JSONDecoder().decode([WidgetBattery].self, from: data) {
            cachedBattery = arr.map { Proto.BatteryEntry(name: $0.name, percent: $0.percent, charging: $0.charging) }
        }
        try? FileManager.default.createDirectory(at: WidgetIO.dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o777])
        objectWillChange.debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.syncWidget() }
            .store(in: &cancellables)
        // Instant detection: macOS tells us the moment the earbuds connect.
        _ = activity
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(deviceConnected(_:device:)))
        requestNotificationAuth()
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    // MARK: Derived
    var title: String {
        if isPro3 { return "OnePlus Buds Pro 3" }
        if let n = currentDeviceName, Proto.isSupportedName(n) { return n }
        return "OnePlus Buds"
    }
    var ancEnabled: Bool { ready && anyInEar != false }
    var wornText: String {
        guard ready else { return "" }
        switch anyInEar { case .some(true): return tr("Worn"); case .some(false): return tr("Not worn"); case .none: return "" }
    }
    var batterySummary: String {
        batteryEntries.map { "\(tr($0.name)): \($0.percent)%\($0.charging ? " ⚡" : "")" }.joined(separator: "  •  ")
    }
    var currentMac: String? {
        if !selectedMac.isEmpty { return selectedMac }
        let t = manualMac.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
    var currentDeviceName: String? { devices.first { $0.mac == selectedMac }?.name }

    // MARK: Popup themes (like the pop-up themes in the mobile app)
    func popupStyle(_ t: PopupTheme) -> PopupStyle {
        PopupStyle(theme: t, glass: liquidGlass, customPath: customMediaPath, blur: customBlur, showBattery: popupShowBattery)
    }

    func tapTheme(_ t: PopupTheme) {
        if carouselOn {
            if let i = carouselThemes.firstIndex(of: t.rawValue) { carouselThemes.remove(at: i) }
            else { carouselThemes.append(t.rawValue) }
        } else {
            popupTheme = t
        }
        if t == .custom && customMediaPath.isEmpty { chooseMedia() }
    }

    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { customMediaPath = url.path }
    }

    func previewPopup() {
        popups.show(.connected(title), theme: effectiveTheme(advance: false), duration: 5, force: true)
    }

    private func effectiveTheme(advance: Bool) -> PopupTheme {
        guard carouselOn else { return popupTheme }
        let list = carouselThemes.compactMap { PopupTheme(rawValue: $0) }
        guard list.count >= 2 else { return popupTheme }
        let ud = UserDefaults.standard
        var idx = ud.integer(forKey: "carouselIndex")
        if advance {
            let last = ud.object(forKey: "carouselStamp") as? Date
            let cal = Calendar.current
            let due: Bool
            switch carouselFreq {
            case "day": due = last == nil || !cal.isDate(last!, inSameDayAs: Date())
            case "week": due = last == nil || !cal.isDate(last!, equalTo: Date(), toGranularity: .weekOfYear)
            default: due = true
            }
            if due { idx += 1; ud.set(idx, forKey: "carouselIndex"); ud.set(Date(), forKey: "carouselStamp") }
        }
        return list[((idx % list.count) + list.count) % list.count]
    }

    private func showConnectedPopup() {
        guard !popupShownSession else { return }
        popupShownSession = true
        popups.show(.connected(title), theme: effectiveTheme(advance: true))
    }

    @objc func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.ready, !self.connecting else { return }
            let name = (device.name ?? "").lowercased()
            let addr = (device.addressString ?? "").lowercased().replacingOccurrences(of: ":", with: "-")
            let cur = (self.currentMac ?? "").lowercased().replacingOccurrences(of: ":", with: "-")
            let isBuds = Proto.isSupportedName(name)
            guard (!cur.isEmpty && addr == cur) || isBuds else { return }
            if cur.isEmpty || addr != cur { self.loadDevices() }
            self.connect()
        }
    }

    // MARK: Widget bridge
    private func syncWidget() {
        var snap = WidgetSnapshot()
        snap.ready = ready
        snap.title = title
        snap.isPro3 = isPro3
        snap.battery = (batteryEntries.isEmpty ? cachedBattery : batteryEntries)
            .map { WidgetBattery(name: $0.name, percent: $0.percent, charging: $0.charging) }
        switch noiseSel {
        case .anc: snap.mode = "anc"
        case .adaptive: snap.mode = "adaptive"
        case .trans: snap.mode = "trans"
        case .off: snap.mode = "off"
        case .none: snap.mode = "none"
        }
        snap.level = levelSel ?? ""
        snap.worn = anyInEar == nil ? -1 : (anyInEar! ? 1 : 0)
        snap.lang = Lang.code
        var cmp = snap
        cmp.updated = Date(timeIntervalSince1970: 0)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard let key = try? enc.encode(cmp), key != lastWidgetKey else { return }
        lastWidgetKey = key
        snap.updated = Date()
        WidgetIO.save(snap)
        widgetReloadWork?.cancel()
        let w = DispatchWorkItem { WidgetCenter.shared.reloadAllTimelines() }
        widgetReloadWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
    }

    /// oneplusbuds://mode/anc|adaptive|trans|off — used by the widget's buttons.
    func handleURL(_ url: URL) {
        guard url.scheme == "oneplusbuds", url.host == "mode" else { return }
        switch url.lastPathComponent {
        case "anc": setAnc()
        case "adaptive": if !isPro3 { setAdaptive() }
        case "trans": setTransparency()
        case "off": setOff()
        default: break
        }
    }

    // MARK: Device list
    func loadDevices() {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        var list: [BudsDevice] = []
        var preferred: BudsDevice?
        for d in paired {
            let name = d.name ?? d.addressString ?? "?"
            let n = name.lowercased()
            guard Proto.isSupportedName(name), let addr = d.addressString else { continue }
            let item = BudsDevice(name: name, mac: addr)
            list.append(item)
            if preferred == nil || n.contains("buds 4") { preferred = item }
        }
        devices = list
        if let p = preferred, !list.contains(where: { $0.mac == selectedMac }) { selectedMac = p.mac }
        if list.isEmpty {
            selectedMac = ""
            status = paired.isEmpty
                ? tr("No paired OnePlus Buds found — pair in System Settings → Bluetooth or type a MAC")
                : tr("Type a MAC, then Connect")
        } else if !ready && !connecting {
            status = tr("Select a device and press Connect")
        }
        updateProfile()
    }

    /// Channel 15 for the verified models; for others try the SDP record of the Melody service UUIDs.
    private func resolveChannel(_ dev: IOBluetoothDevice) -> UInt8 {
        if Proto.usesFixedChannel(dev.name ?? "") { return Proto.channel }
        for s in Proto.serviceUUIDs {
            guard let u = UUID(uuidString: s) else { continue }
            var bytes = [UInt8](repeating: 0, count: 16)
            withUnsafeBytes(of: u.uuid) { for i in 0..<16 { bytes[i] = $0[i] } }
            let sdp = IOBluetoothSDPUUID(data: Data(bytes))
            guard let rec = dev.getServiceRecord(for: sdp) else { continue }
            var id: BluetoothRFCOMMChannelID = 0
            if rec.getRFCOMMChannelID(&id) == kIOReturnSuccess, id > 0 {
                log(Array("SDP \(s) -> channel \(id)".utf8), incoming: false)
                return UInt8(id)
            }
        }
        dev.performSDPQuery(nil)   // fill the SDP cache for the next attempt
        return Proto.channel
    }

    func updateProfile() {
        let name = currentDeviceName ?? ""
        isPro3 = name.range(of: "3 Pro", options: .caseInsensitive) != nil
    }

    private func isDeviceConnected(_ mac: String) -> Bool {
        IOBluetoothDevice(addressString: normalize(mac))?.isConnected() ?? false
    }

    private func normalize(_ mac: String) -> String {
        mac.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Startup
    func start() {
        loadDevices()
        guard let mac = currentMac else { return }
        if isDeviceConnected(mac) { connect() }
        else {
            status = tr("Waiting for earbuds to connect to macOS…")
            startReconnectWatcher()
        }
    }

    func shutdown() {
        wasConnected = false
        reconnectTimer?.invalidate()
        pollTimer?.invalidate()
        closeChannel()
    }

    // MARK: Connect
    func connect() {
        guard let mac = currentMac else { status = tr("Pick a device or type a MAC first"); return }
        guard !connecting else { return }
        guard let dev = IOBluetoothDevice(addressString: normalize(mac)) else {
            status = tr("Invalid MAC address"); return
        }
        updateProfile()
        if isDeviceConnected(mac) { showConnectedPopup() }
        connecting = true
        ready = false
        bothInCase = nil; anyInEar = nil
        reconnectTimer?.invalidate()
        pollTimer?.invalidate()
        closeChannel()
        rxBuffer.removeAll()
        status = trf("Connecting to %@…", mac)

        connectToken += 1
        let token = connectToken
        var ch: IOBluetoothRFCOMMChannel?
        let r = dev.openRFCOMMChannelAsync(&ch, withChannelID: BluetoothRFCOMMChannelID(resolveChannel(dev)), delegate: self)
        if r != kIOReturnSuccess {
            connecting = false
            status = trf("Waiting for earbuds to connect… (error %d)", Int(r))
            startReconnectWatcher()
            return
        }
        channel = ch

        // Give up after 8 s and fall back to the watcher.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.connectToken == token, self.connecting else { return }
            self.closeChannel()
            self.connecting = false
            self.status = tr("Waiting for earbuds to connect…")
            self.startReconnectWatcher()
        }
    }

    private func closeChannel() {
        let ch = channel
        channel = nil
        _ = ch?.setDelegate(nil)
        _ = ch?.close()   // only the RFCOMM channel — never the baseband, audio must stay connected
    }

    // IOBluetoothRFCOMMChannelDelegate
    @objc func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        DispatchQueue.main.async {
            guard rfcommChannel === self.channel else { return }
            if error != kIOReturnSuccess {
                self.connecting = false
                self.channel = nil
                self.status = trf("Waiting for earbuds to connect… (error %d)", Int(error))
                self.startReconnectWatcher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self, !self.ready, !self.connecting, let mac = self.currentMac,
                          self.isDeviceConnected(mac) else { return }
                    self.connect()
                }
                return
            }
            self.handshake()
        }
    }

    @objc func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        DispatchQueue.main.async {
            guard rfcommChannel === self.channel else { return }
            self.rxBuffer += bytes
            for frame in Proto.extractFrames(&self.rxBuffer) {
                self.log(frame, incoming: true)
                self.handlePacket(frame)
            }
        }
    }

    @objc func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        DispatchQueue.main.async {
            guard rfcommChannel === self.channel else { return }
            self.channel = nil
            self.onDisconnected()
        }
    }

    private func handshake() {
        send(Proto.hello)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.channel != nil else { return }
            self.send(Proto.register)
            // The earbuds broadcast their initial state after REGISTER; give it a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.channel != nil else { return }
                self.onConnected()
            }
        }
    }

    private func onConnected() {
        connecting = false
        ready = true
        wasConnected = true
        connectedAt = Date()
        batteryNotificationShown = false
        reconnectTimer?.invalidate()
        status = trf("Connected to %@", currentMac ?? "")
        requestBattery()
        requestFullState()
        startPollTimer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.batteryNotificationShown, self.ready else { return }
            self.batteryNotificationShown = true
            self.notify(trf("%@ Connected", self.title), self.lastBatterySummary ?? tr("Connected successfully"))
        }
    }

    private func onDisconnected() {
        connecting = false
        if wasConnected {
            wasConnected = false
            batteryNotificationShown = false
            notify(trf("%@ Disconnected", title),
                   lastBatterySummary.map { trf("Last battery: %@", $0) } ?? tr("Bluetooth connection lost."))
            popups.show(.disconnected(title), duration: 3)
        }
        ready = false
        popupShownSession = false
        batteryEntries = []
        pollTimer?.invalidate()
        status = tr("Reconnecting…")
        startReconnectWatcher()
    }

    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, self.ready else { return }
            self.requestBattery()
            self.requestAncNow()
        }
    }

    private func startReconnectWatcher() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if self.ready || self.connecting { return }
            guard let mac = self.currentMac else { return }
            if self.isDeviceConnected(mac) {
                t.invalidate()
                self.connect()
            }
        }
    }

    // MARK: Sending
    func send(_ packet: [UInt8]) {
        guard let ch = channel else { return }
        var p = packet
        let r = p.withUnsafeMutableBytes { raw -> IOReturn in
            ch.writeSync(raw.baseAddress, length: UInt16(packet.count))
        }
        if r != kIOReturnSuccess { status = trf("Send failed (error %d)", Int(r)) }
        log(packet, incoming: false)
    }

    func requestBattery() { send(Proto.battery) }
    func requestAncNow() { send(Proto.getAncNow); send(Proto.getAncAuto) }
    func requestFullState() {
        requestBattery()
        requestAncNow()
        send(Proto.getEq)
        send(Proto.getBwValue)
        send(Proto.getBwSwitch)
        send(Proto.getWear)
        send(Proto.getCustomEq)
        send(Proto.getGestures)
    }

    private func requestFullStateThrottled() {
        guard ready else { return }
        let now = Date()
        if now.timeIntervalSince(lastStateRequest) < 0.25 { return }
        lastStateRequest = now
        requestFullState()
    }

    /// Send a command and show "…" until the earbuds ack it.
    func command(_ packet: [UInt8], _ label: String) {
        guard ready else { status = tr("Not connected"); return }
        lastUserCommand = Date()
        let label = tr(label)
        if packet.count > 4 { pendingAck[packet[4]] = label }
        send(packet)
        status = label + "…"
    }

    // MARK: Incoming
    private func handlePacket(_ d: [UInt8]) {
        if d.count >= 10 && d[5] == 0x84 {
            let cmd = d[4]
            if let label = pendingAck.removeValue(forKey: cmd) {
                status = d[9] == 0 ? "\(label) ✓" : "\(label) failed (error \(d[9]))"
            }
        }

        if Proto.hasMarker(d, 0x0F, 0x81) { applyEq(d) }
        if Proto.hasMarker(d, 0x24, 0x81) { applyBassValue(d) }
        if Proto.hasMarker(d, 0x0D, 0x81) { applyBassOn(d) }
        if Proto.hasMarker(d, 0x81, 0x25) { applyBattery(d) }
        if Proto.hasMarker(d, 0x22, 0x81) { applyCustomEqList(d) }
        if Proto.hasMarker(d, 0x08, 0x81) { applyGestures(d) }

        if let s = Proto.decodeAncReply(d) { applyAnc(s) }
        if let s = Proto.decodeAncMode(d) { applyAnc(s) }
        if let lvl = Proto.decodeAncAutoLevel(d) ?? Proto.decodeAncReplyAutoLevel(d) { applyAutoLevel(lvl) }

        if let w = Proto.decodeWear(d) { applyWear(w) }

        let isGesture = d.count >= 10 && d[4] == 0x04 && d[5] == 0x02 && d[9] == 0xF1
        let isChange = d.count >= 6 && d[5] == 0x05
        if isGesture {
            tapSide = d.count > 10 ? d[10] : 0
            tapCounter += 1
            activity.gesture(side: tapSide, data: d)
        }
        if isGesture || isChange {
            requestFullStateThrottled()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.ready else { return }
                self.requestAncNow()
            }
        }
    }

    private func applyAnc(_ s: Proto.AncState) {
        ancAuto = s.auto
        let beforeMode = noiseSel, beforeLevel = levelSel
        if s.off {
            noiseSel = .off; levelSel = nil; autoSub = nil
        } else if s.trans {
            noiseSel = .trans; levelSel = nil; autoSub = nil
        } else if s.adaptive && !isPro3 {
            noiseSel = .adaptive; levelSel = nil; autoSub = nil
        } else if s.anc {
            noiseSel = .anc
            if ["High", "Moderate", "Low", "Auto"].contains(s.level) { levelSel = s.level }
            if !s.auto { autoSub = nil }
        }
        // Changed from the earbuds themselves (touch gesture / phone), not by this app → show a HUD.
        let external = ready
            && Date().timeIntervalSince(lastUserCommand) > 1.5
            && Date().timeIntervalSince(connectedAt) > 2.5
        if external && (noiseSel != beforeMode || (noiseSel == .anc && levelSel != beforeLevel)) {
            switch noiseSel {
            case .anc: popups.show(.info(icon: "ear.badge.waveform",
                                         text: tr("Noise Cancellation") + (levelSel.map { " · \(tr($0))" } ?? "")), duration: 2)
            case .trans: popups.show(.info(icon: "ear.and.waveform", text: tr("Transparency")), duration: 2)
            case .adaptive: popups.show(.info(icon: "sparkles", text: tr("Adaptive")), duration: 2)
            case .off: popups.show(.info(icon: "ear", text: tr("Noise control off")), duration: 2)
            case .none: break
            }
        }
        markOffWhenNotWorn()
    }

    private func applyAutoLevel(_ level: String) {
        guard ancAuto else { return }
        autoSub = level
    }

    private func markOffWhenNotWorn() {
        if anyInEar == false { noiseSel = .off; levelSel = nil; autoSub = nil }
    }

    private func applyWear(_ w: Proto.WearState) {
        let was = anyInEar
        if let was, was != w.anyInEar, ready, Date().timeIntervalSince(connectedAt) > 2.5 {
            popups.show(.info(icon: w.anyInEar ? "ear" : "earbuds",
                              text: w.anyInEar ? tr("Earbuds in ear") : tr("Earbuds removed")), duration: 1.8)
        }
        bothInCase = w.bothInCase
        anyInEar = w.anyInEar
        markOffWhenNotWorn()
        if was != anyInEar { requestFullStateThrottled() }
    }

    private func applyEq(_ d: [UInt8]) {
        if let p = Proto.decodeEqPreset(d) { eqPreset = p }
    }

    private func applyBassValue(_ d: [UInt8]) {
        if let v = Proto.decodeBassWaveValue(d) { bassValue = Double(v) }
    }

    private func applyBassOn(_ d: [UInt8]) {
        bassOn = Proto.decodeBassWaveOn(d) == true
    }

    private func applyBattery(_ d: [UInt8]) {
        guard let entries = Proto.decodeBattery(d) else { return }
        batteryEntries = entries
        lastBatterySummary = batterySummary
        if entries != cachedBattery {
            cachedBattery = entries
            let arr = entries.map { WidgetBattery(name: $0.name, percent: $0.percent, charging: $0.charging) }
            if let data = try? JSONEncoder().encode(arr) { UserDefaults.standard.set(data, forKey: "cachedBattery") }
        }
        if !batteryNotificationShown {
            batteryNotificationShown = true
            notify(trf("%@ Connected", title), batterySummary)
        }
    }

    private func applyCustomEqList(_ d: [UInt8]) {
        let list = Proto.decodeCustomEqList(d)
        let hadSlots = !customSlots.isEmpty
        let oldActive = customSlots.first(where: { $0.isSelected })?.id
        let newActive = list.first(where: { $0.isSelected })?.id
        if list != customSlots { customSlots = list }
        // Pull the values that are really on the earbuds into the sliders.
        if !hadSlots || oldActive != newActive || selectedSlot == nil
            || !list.contains(where: { $0.id == selectedSlot }) {
            selectedSlot = (list.first(where: { $0.isSelected }) ?? list.first)?.id
            loadSlotValues()
        }
    }

    private func loadSlotValues() {
        guard let id = selectedSlot, let eq = customSlots.first(where: { $0.id == id }) else { return }
        bands = (0..<6).map { $0 < eq.db.count ? Double(eq.db[$0]) : 0 }
        eqName = eq.name
    }

    func selectSlot(_ id: UInt8) {
        selectedSlot = id
        loadSlotValues()
    }

    private func applyGestures(_ d: [UInt8]) {
        let entries = Proto.decodeGestures(d)
        guard !entries.isEmpty else { return }
        for e in entries { gestureMap[GestureKey(side: e.side, cat: e.category, gid: e.gesture)] = e.action }
    }

    // MARK: User actions — noise control
    func setAnc() {
        noiseSel = .anc
        if !isPro3 && levelSel == nil { levelSel = "Auto" }
        command(Proto.anc(0x02), isPro3 ? "ANC on" : "Noise Cancellation")
    }
    func setAdaptive() { noiseSel = .adaptive; levelSel = nil; autoSub = nil; command(Proto.ancAdaptive(), "Adaptive") }
    func setTransparency() { noiseSel = .trans; levelSel = nil; autoSub = nil; command(Proto.anc(0x04), "Transparency") }
    func setOff() { noiseSel = .off; levelSel = nil; autoSub = nil; command(Proto.anc(0x01), "ANC off") }
    func setLevel(_ name: String) {
        let map: [String: (UInt8, String)] = [
            "High": (0x10, "ANC High"), "Moderate": (0x20, "ANC Moderate"),
            "Low": (0x40, "ANC Low"), "Auto": (0x80, "ANC Auto")
        ]
        guard let (code, label) = map[name] else { return }
        levelSel = name
        noiseSel = .anc
        if name != "Auto" { autoSub = nil }
        command(Proto.ancLevel(code), label)
    }

    // MARK: EQ presets
    var eqPresets: [ActionItem] {
        isPro3
            ? [ActionItem(id: 0x00, label: "Balanced"), ActionItem(id: 0x01, label: "Bold"),
               ActionItem(id: 0x02, label: "Serenade"), ActionItem(id: 0x03, label: "Bass"),
               ActionItem(id: 0x07, label: "DynAudio")]
            : [ActionItem(id: 0x00, label: "Balanced"), ActionItem(id: 0x01, label: "Clear Vocals"),
               ActionItem(id: 0x02, label: "Bass")]
    }
    func setEq(_ item: ActionItem) {
        eqPreset = item.id
        command(Proto.eq(item.id), "EQ \(item.label)")
    }

    // MARK: BassWave
    func setBassOn(_ on: Bool) {
        bassOn = on
        guard ready else { return }
        let v = Int(bassValue.rounded())
        let vs = "\(v > 0 ? "+" : "")\(v)"
        command(Proto.featureSwitch(0x1D, on: on), on ? trf("BassWave on (%@)", vs) : tr("BassWave off"))
        if on { send(Proto.bassWave(v)) }
    }
    func commitBassValue() {
        guard ready, bassOn else { return }
        let v = Int(bassValue.rounded())
        command(Proto.bassWave(v), trf("BassWave %@", "\(v > 0 ? "+" : "")\(v)"))
    }

    // MARK: Custom EQ
    private var effectiveEqName: String {
        let t = eqName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Custom" : t
    }
    func createCustomEq() {
        guard ready else { status = tr("Not connected"); return }
        command(Proto.customEq(name: effectiveEqName, db: bands.map { Int($0.rounded()) }, op: 1, eqId: 0),
                trf("Create EQ '%@'", effectiveEqName))
        send(Proto.getCustomEq)
    }
    func selectCustomEq() {
        guard ready else { status = tr("Not connected"); return }
        guard let id = selectedSlot, let eq = customSlots.first(where: { $0.id == id }) else {
            status = tr("Slot is empty — create an EQ first"); return
        }
        command(Proto.customEq(name: eq.name, db: eq.db, op: 2, eqId: id), trf("Select EQ '%@' (slot %d)", eq.name, Int(id)))
    }
    func deleteCustomEq() {
        guard ready else { status = tr("Not connected"); return }
        guard let id = selectedSlot, let eq = customSlots.first(where: { $0.id == id }) else {
            status = tr("Slot is empty — nothing to delete"); return
        }
        command(Proto.customEq(name: eq.name, db: eq.db, op: 3, eqId: id), trf("Delete EQ '%@' (slot %d)", eq.name, Int(id)))
        send(Proto.getCustomEq)
    }

    // MARK: Gestures
    static let singleTap   = [ActionItem(id: 0x01, label: "Play / Pause"), ActionItem(id: 0x00, label: "None")]
    static let doubleTap   = [ActionItem(id: 0x06, label: "Next track"), ActionItem(id: 0x05, label: "Previous track"),
                              ActionItem(id: 0x01, label: "Play / Pause"), ActionItem(id: 0x03, label: "Voice Assistant"),
                              ActionItem(id: 0x00, label: "None")]
    static let tripleTap   = [ActionItem(id: 0x03, label: "Voice Assistant"), ActionItem(id: 0x05, label: "Previous track"),
                              ActionItem(id: 0x06, label: "Next track"), ActionItem(id: 0x00, label: "None")]
    static let slide       = [ActionItem(id: 0x08, label: "Volume control"), ActionItem(id: 0x00, label: "None")]
    static let touchHold   = [ActionItem(id: 0x07, label: "Noise control"), ActionItem(id: 0x03, label: "Voice Assistant"),
                              ActionItem(id: 0x00, label: "None")]
    static let callDouble  = [ActionItem(id: 0x1D, label: "Answer / End call"), ActionItem(id: 0x00, label: "None")]
    static let callHold    = [ActionItem(id: 0x1C, label: "Decline call"), ActionItem(id: 0x00, label: "None")]

    func gestureAction(cat: UInt8, gid: UInt8, def: UInt8) -> UInt8 {
        gestureMap[GestureKey(side: gestureSide, cat: cat, gid: gid)] ?? def
    }

    func setGesture(cat: UInt8, gid: UInt8, name: String, item: ActionItem) {
        gestureMap[GestureKey(side: gestureSide, cat: cat, gid: gid)] = item.id
        let side = tr(gestureSide == 1 ? "Left" : "Right")
        command(Proto.setGesture(side: gestureSide, category: cat, gesture: gid, action: item.id),
                "\(side) \(name) -> \(tr(item.label))")
    }

    // MARK: Login item
    func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = trf("Login item failed: %@", error.localizedDescription)
        }
        startAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notifications
    private func requestNotificationAuth() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ title: String, _ body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let key = "\(title)::\(body)"
        if key == lastNotifKey && Date().timeIntervalSince(lastNotifTime) < 3 { return }
        lastNotifKey = key; lastNotifTime = Date()
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // MARK: Packet log
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    private func log(_ data: [UInt8], incoming: Bool) {
        guard !data.isEmpty else { return }
        packetCount += 1
        let time = Self.timeFmt.string(from: Date())
        let dir = incoming ? "[RECV]" : "[SEND]"
        let hex = Proto.hex(data)
        let ann = Proto.annotate(data, incoming: incoming)
        let len = String(format: "%2d", data.count)
        let line = ann.isEmpty
            ? "[\(time)] \(dir) (\(len)B) \(hex)"
            : "[\(time)] \(dir) (\(len)B) \(hex.padding(toLength: 36, withPad: " ", startingAt: 0)) | \(ann)"
        logLines.append(LogLine(text: line))
        if logLines.count > maxLines { logLines.removeFirst(logLines.count - maxLines) }
        appendToFile(line)
    }

    private func appendToFile(_ line: String) {
        let data = Data((line + "\n").utf8)
        DispatchQueue.global(qos: .utility).async { [logFileURL] in
            if let h = try? FileHandle(forWritingTo: logFileURL) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    func clearLog() { logLines.removeAll(); packetCount = 0 }
    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logLines.map(\.text).joined(separator: "\n"), forType: .string)
    }

    func sendHex(_ text: String) -> String? {
        guard ready else { return "Not connected to earbuds." }
        let raw = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard !raw.isEmpty, raw.count % 2 == 0 else { return "Invalid hex string (needs an even number of hex characters)." }
        var bytes: [UInt8] = []
        var idx = raw.startIndex
        while idx < raw.endIndex {
            let next = raw.index(idx, offsetBy: 2)
            guard let b = UInt8(raw[idx..<next], radix: 16) else { return "Invalid hex digits." }
            bytes.append(b); idx = next
        }
        send(bytes)
        return nil
    }

    @Published var probing = false
    func probeFeatures() {
        guard ready, !probing else { return }
        probing = true
        logLines.append(LogLine(text: "─── PROBE STEP 1: Querying Function Codes 0x01..0x35 ───"))
        var packets: [[UInt8]] = []
        for fn in UInt8(0x01)...UInt8(0x35) where fn != 0x06 {
            packets.append([0xAA, 0x07, 0x00, 0x00, fn, 0x01, 0x00, 0x00, 0x00])
        }
        for id in UInt8(0x01)...UInt8(0x25) where id != 0x1D {
            packets.append([0xAA, 0x09, 0x00, 0x00, 0x0D, 0x01, 0x00, 0x02, 0x00, 0x01, id])
        }
        for (fn, side) in [(0x10, 1), (0x10, 2), (0x12, 1), (0x12, 2), (0x14, 1), (0x14, 2)] {
            packets.append([0xAA, 0x08, 0x00, 0x00, UInt8(fn), 0x01, 0x00, 0x01, 0x00, UInt8(side)])
        }
        Task { @MainActor in
            for p in packets {
                self.send(p)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            self.logLines.append(LogLine(text: "─── PROBE COMPLETE: Check [RECV] lines above for replies ───"))
            self.probing = false
        }
    }
}
