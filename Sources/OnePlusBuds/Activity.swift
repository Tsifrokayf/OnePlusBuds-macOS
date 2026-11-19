import Foundation
import CoreAudio
import AppKit
import SwiftUI

/// Watches what the earbuds do to the Mac (volume buttons, play/pause) and shows a matching HUD.
/// - Volume: CoreAudio listener on the default output device (only when it is a Bluetooth device).
/// - Play / pause: MediaRemote notification when available, otherwise "device is running" changes.
final class ActivityMonitor {
    private unowned let model: AppModel
    private var dev: AudioObjectID = 0
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemBlock: AudioObjectPropertyListenerBlock?
    private var lastVol: Float = -1
    private var lastMute = false
    private var lastRunning: Bool?
    private var playWork: DispatchWorkItem?
    private var lastPlayShown = (state: false, at: Date.distantPast)
    private var mediaRemoteWorks = false
    private var lastGestureAt = Date.distantPast
    private var lastAction: UInt8 = 0
    private var lastTitle = ""
    private var mrGet: (@convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void)?

    init(model: AppModel) {
        self.model = model
        attach()
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        let b: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }
        systemBlock = b
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, b)
        setupMediaRemote()
    }

    private static func addr(_ sel: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    private func has(_ id: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a; return AudioObjectHasProperty(id, &a)
    }

    private func defaultOutput() -> AudioObjectID {
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(0); var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private func isBluetooth(_ id: AudioObjectID) -> Bool {
        var a = Self.addr(kAudioDevicePropertyTransportType)
        var t = UInt32(0); var size = UInt32(4)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &t) == noErr else { return false }
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private func volumeElements(_ id: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let main = Self.addr(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput)
        if has(id, main) { return [main] }
        return [1, 2].map { Self.addr(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: AudioObjectPropertyElement($0)) }
            .filter { has(id, $0) }
    }

    private func readVolume(_ id: AudioObjectID) -> Float? {
        let els = volumeElements(id)
        guard !els.isEmpty else { return nil }
        var sum: Float = 0
        for var a in els {
            var v = Float32(0); var size = UInt32(4)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr else { return nil }
            sum += v
        }
        return sum / Float(els.count)
    }

    private func readMute(_ id: AudioObjectID) -> Bool {
        var a = Self.addr(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard has(id, a) else { return false }
        var v = UInt32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v != 0
    }

    private func readRunning(_ id: AudioObjectID) -> Bool {
        var a = Self.addr(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var v = UInt32(0); var size = UInt32(4)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v)
        return v != 0
    }

    private func attach() {
        for (id, a, b) in listeners { var a = a; AudioObjectRemovePropertyListenerBlock(id, &a, DispatchQueue.main, b) }
        listeners = []
        dev = defaultOutput()
        guard dev != 0, isBluetooth(dev) else { lastVol = -1; lastRunning = nil; return }
        lastVol = readVolume(dev) ?? -1
        lastMute = readMute(dev)
        lastRunning = readRunning(dev)
        let vb: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        let rb: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.runningChanged() }
        var targets = volumeElements(dev).map { ($0, vb) }
        targets.append((Self.addr(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput), vb))
        targets.append((Self.addr(kAudioDevicePropertyDeviceIsRunningSomewhere), rb))
        for (a0, b) in targets where has(dev, a0) {
            var a = a0
            if AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main, b) == noErr { listeners.append((dev, a0, b)) }
        }
    }

    private func volumeChanged() {
        guard dev != 0, let v = readVolume(dev) else { return }
        let mute = readMute(dev)
        if abs(v - lastVol) < 0.001 && mute == lastMute { return }
        lastVol = v; lastMute = mute
        guard model.earbudHUD else { return }
        // Only when it came from the earbuds: a touch gesture just happened (or is about to be reported).
        let t = Date()
        if t.timeIntervalSince(lastGestureAt) < 2.0 {
            presentVolume()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.lastGestureAt > t else { return }
                self.presentVolume()
            }
        }
    }

    private func presentVolume() {
        guard dev != 0, let v = readVolume(dev) else { return }
        model.popups.show(.volume(level: v, muted: readMute(dev)), duration: 1.6, refresh: true)
    }

    private func runningChanged() {
        playWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.dev != 0 else { return }
            let r = self.readRunning(self.dev)
            defer { self.lastRunning = r }
            guard self.lastRunning != nil, r != self.lastRunning, !self.mediaRemoteWorks else { return }
            self.showPlay(r)
        }
        playWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: w)
    }

    func showPlay(_ playing: Bool) {
        guard model.earbudHUD, model.ready || dev != 0 else { return }
        if lastPlayShown.state == playing && Date().timeIntervalSince(lastPlayShown.at) < 2.5 { return }
        lastPlayShown = (playing, Date())
        model.popups.show(.info(icon: playing ? "play.fill" : "pause.fill",
                                text: tr(playing ? "Playing" : "Paused")), duration: 1.6)
    }

    // MARK: MediaRemote (private framework; may return nothing on newer macOS — then the fallback above is used)
    private func setupMediaRemote() {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY) else { return }
        typealias Reg = @convention(c) (DispatchQueue) -> Void
        typealias Get = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
        if let s = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            unsafeBitCast(s, to: Reg.self)(DispatchQueue.main)
        }
        if let s = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") {
            mrGet = unsafeBitCast(s, to: Get.self)
        }
        typealias Info = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
        if let s = dlsym(h, "MRMediaRemoteGetNowPlayingInfo") {
            let getInfo = unsafeBitCast(s, to: Info.self)
            NotificationCenter.default.addObserver(
                forName: Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
                object: nil, queue: .main) { [weak self] _ in
                getInfo(DispatchQueue.main) { dict in
                    guard let self, let d = dict as? [String: Any],
                          let title = d["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else { return }
                    let changed = title != self.lastTitle
                    self.lastTitle = title
                    // Show the new track only when the earbuds caused the change.
                    guard changed, self.model.earbudHUD, Date().timeIntervalSince(self.lastGestureAt) < 3 else { return }
                    let artist = d["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                    let icon = self.lastAction == 0x05 ? "backward.fill" : "forward.fill"
                    self.model.popups.show(.info(icon: icon, text: artist.isEmpty ? title : "\(title) — \(artist)"), duration: 2.2)
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object: nil, queue: .main) { [weak self] _ in
            guard let self, let get = self.mrGet else { return }
            get(DispatchQueue.main) { playing in
                self.mediaRemoteWorks = true
                self.showPlay(playing)
            }
        }
    }

    // MARK: Touch gestures
    /// Shows the HUD for a gesture immediately. The event carries the touched side and (we try to find) the
    /// gesture id, which we map to the action configured for it; the real outcome (play state, volume, ANC,
    /// track title) then morphs the same HUD.
    func gesture(side: UInt8, data d: [UInt8]) {
        lastGestureAt = Date()
        // Keep raw bytes so the gesture decoding can be refined.
        if let f = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/Users/Shared/OnePlusBuds/gesture.log")) {
            f.seekToEndOfFile(); f.write(Data("\(Date()) \(Proto.hex(d))\n".utf8)); try? f.close()
        } else {
            try? Data("\(Date()) \(Proto.hex(d))\n".utf8).write(to: URL(fileURLWithPath: "/Users/Shared/OnePlusBuds/gesture.log"))
        }
        guard model.earbudHUD else { return }
        var action: UInt8?
        if d.count > 12 {
            for i in 11..<(d.count - 1) {
                if let a = model.gestureMap[GestureKey(side: side, cat: d[i], gid: d[i + 1])], a != 0 { action = a; break }
            }
        }
        lastAction = action ?? 0
        let sideName = side == 1 ? tr("Left earbud") : (side == 2 ? tr("Right earbud") : tr("Earbud"))
        let (icon, text): (String, String)
        switch action {
        case 0x01: (icon, text) = ("playpause.fill", tr("Play / Pause"))
        case 0x05: (icon, text) = ("backward.fill", tr("Previous track"))
        case 0x06: (icon, text) = ("forward.fill", tr("Next track"))
        case 0x03: (icon, text) = ("mic.fill", tr("Voice Assistant"))
        case 0x08: (icon, text) = ("speaker.wave.2.fill", tr("Volume control"))
        case 0x07: (icon, text) = ("ear.and.waveform", tr("Noise control"))
        case 0x1D: (icon, text) = ("phone.fill", tr("Answer / End call"))
        case 0x1C: (icon, text) = ("phone.down.fill", tr("Decline call"))
        default: (icon, text) = ("hand.tap.fill", sideName)
        }
        model.popups.show(.info(icon: icon, text: text), duration: 1.4)
    }
}
