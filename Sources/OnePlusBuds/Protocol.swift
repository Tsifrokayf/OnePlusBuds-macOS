import Foundation

/// Packet builders / decoders for the OnePlus Buds RFCOMM protocol
/// (direct port of BudsConnection.cs from the Windows companion).
enum Proto {
    static let channel: UInt8 = 15

    /// Name patterns of earbuds that speak the same HeyMelody protocol family
    /// (OnePlus Buds / Nord Buds, OPPO Enco). Newer models are verified on Buds 4 / Pro 3 only.
    static func isSupportedName(_ name: String) -> Bool {
        let n = name.lowercased()
        if n.contains("oneplus") && n.contains("buds") { return true }
        if n.contains("nord buds") { return true }
        if n.contains("oppo") && n.contains("enco") { return true }
        if n.hasPrefix("enco ") { return true }
        return false
    }
    /// Models where the fixed channel 15 is known to work.
    static func usesFixedChannel(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("buds 4") || n.contains("3 pro") || n.contains("pro 3")
    }
    /// Service UUIDs the mobile app uses for older models (looked up via SDP for the RFCOMM channel).
    static let serviceUUIDs = [
        "5ce76944-230f-4694-bad6-a24d3038665c",
        "0000079A-D102-11E1-9B23-00025B00A5A5", "0100079A-D102-11E1-9B23-00025B00A5A5",
        "0200079A-D102-11E1-9B23-00025B00A5A5", "0000079C-D102-11E1-9B23-00025B00A5A5",
        "0100079C-D102-11E1-9B23-00025B00A5A5", "00001107-D102-11E1-9B23-00025B00A5A5"
    ]

    // MARK: Fixed packets
    static let hello: [UInt8]    = [0xAA, 0x07, 0x00, 0x00, 0x00, 0x01, 0x23, 0x00, 0x00, 0x12]
    static let register: [UInt8] = [0xAA, 0x0C, 0x00, 0x00, 0x00, 0x85, 0x41, 0x05, 0x00, 0x00, 0xB5, 0x50, 0xA0, 0x69]

    static let battery:     [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x06, 0x01, 0x25, 0x00, 0x00]
    static let getCustomEq: [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x22, 0x01, 0x00, 0x00, 0x00]
    static let getEq:       [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x0F, 0x01, 0x00, 0x00, 0x00]
    static let getBwValue:  [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x24, 0x01, 0x00, 0x00, 0x00]
    static let getGestures: [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x08, 0x01, 0x00, 0x00, 0x00]
    static let getBwSwitch: [UInt8] = [0xAA, 0x09, 0x00, 0x00, 0x0D, 0x01, 0x00, 0x02, 0x00, 0x01, 0x1D]
    static let getWear:     [UInt8] = [0xAA, 0x07, 0x00, 0x00, 0x09, 0x01, 0x00, 0x00, 0x00]
    static let getAncNow:   [UInt8] = [0xAA, 0x09, 0x00, 0x00, 0x0C, 0x01, 0x00, 0x02, 0x00, 0x01, 0x01]
    static let getAncAuto:  [UInt8] = [0xAA, 0x09, 0x00, 0x00, 0x0C, 0x01, 0x00, 0x02, 0x00, 0x04, 0x01]

    // MARK: Builders
    /// mode: 0x02 = ANC on, 0x01 = off, 0x04 = transparency
    static func anc(_ mode: UInt8) -> [UInt8] {
        [0xAA, 0x0A, 0x00, 0x00, 0x04, 0x04, 0x42, 0x03, 0x00, 0x01, 0x01, mode]
    }
    static func ancMask(_ mask: UInt16) -> [UInt8] {
        [0xAA, 0x0B, 0x00, 0x00, 0x04, 0x04, 0x42, 0x04, 0x00, 0x01, 0x01, UInt8(mask & 0xFF), UInt8(mask >> 8)]
    }
    /// hi: 0x10 High, 0x20 Moderate, 0x40 Low, 0x80 Auto
    static func ancLevel(_ hi: UInt8) -> [UInt8] { ancMask(UInt16(hi)) }
    static func ancAdaptive() -> [UInt8] { ancMask(0x0800) }
    static func eq(_ preset: UInt8) -> [UInt8] {
        [0xAA, 0x08, 0x00, 0x00, 0x06, 0x04, 0x00, 0x01, 0x00, preset]
    }
    static func bassWave(_ value: Int) -> [UInt8] {
        let v = max(-5, min(5, value))
        return [0xAA, 0x0A, 0x00, 0x00, 0x1B, 0x04, 0x00, 0x03, 0x00, 0xFB, 0x05, UInt8(bitPattern: Int8(v))]
    }
    static func featureSwitch(_ feature: UInt8, on: Bool) -> [UInt8] {
        [0xAA, 0x09, 0x00, 0x00, 0x03, 0x04, 0x00, 0x02, 0x00, feature, on ? 1 : 0]
    }
    static func setGesture(side: UInt8, category: UInt8, gesture: UInt8, action: UInt8) -> [UInt8] {
        [0xAA, 0x0B, 0x00, 0x00, 0x08, 0x04, 0x00, 0x04, 0x00, side, category, gesture, action]
    }

    static let eqBands: [Int] = [62, 250, 1000, 4000, 8000, 16000]

    /// op: 1 = create, 2 = select, 3 = delete
    static func customEq(name: String, db: [Int], op: UInt8 = 1, eqId: UInt8 = 0) -> [UInt8] {
        let nameB = Array(name.utf8)
        var pl: [UInt8] = [op, 0xFA /* -6 */, 6, eqId, UInt8(nameB.count)]
        pl += nameB
        pl.append(UInt8(eqBands.count))
        for i in 0..<eqBands.count {
            let f = eqBands[i]
            pl.append(UInt8(f & 0xFF))
            pl.append(UInt8((f >> 8) & 0xFF))
            let g = max(-6, min(6, i < db.count ? db[i] : 0))
            pl.append(UInt8(bitPattern: Int8(g)))
        }
        let plen = pl.count
        var body: [UInt8] = [0x00, 0x00, 0x18, 0x04, 0x00, UInt8(plen & 0xFF), UInt8((plen >> 8) & 0xFF)]
        body += pl
        return [0xAA, UInt8(body.count)] + body
    }

    // MARK: Helpers
    static func hex(_ d: [UInt8]) -> String { d.map { String(format: "%02X", $0) }.joined(separator: " ") }

    static func indexOf(_ hay: [UInt8], _ needle: [UInt8]) -> Int {
        if needle.isEmpty || hay.count < needle.count { return -1 }
        var i = 0
        while i + needle.count <= hay.count {
            var ok = true
            for j in 0..<needle.count where hay[i + j] != needle[j] { ok = false; break }
            if ok { return i }
            i += 1
        }
        return -1
    }

    static func hasMarker(_ d: [UInt8], _ a: UInt8, _ b: UInt8) -> Bool { indexOf(d, [a, b]) >= 0 }

    // MARK: Packet annotation (for the log window)
    static func annotate(_ d: [UInt8], incoming: Bool) -> String {
        guard d.count >= 6 else { return "" }
        let cmdLo = d[4], cmdHi = d[5]
        let cmd16 = Int(cmdLo) | (Int(cmdHi) << 8)
        let last = d[d.count - 1]

        if !incoming {
            switch cmd16 {
            case 0x0100: return "Hello handshake"
            case 0x8500: return "Register handshake"
            case 0x0404: return "Set ANC (cmd 0x0404)"
            case 0x0408 where d.count >= 4:
                return "Set Gesture (side \(d[d.count-4]), cat \(d[d.count-3]), gid \(d[d.count-2]) -> act \(last))"
            case 0x0406: return "Set EQ preset \(last)"
            case 0x041B: return "Set BassWave \(Int8(bitPattern: last))"
            case 0x0403 where d.count >= 2: return "Set Switch \(d[d.count-2])=\(last == 1 ? "on" : "off")"
            case 0x0418: return "Set Custom EQ"
            case 0x0106: return "Query Battery"
            case 0x0108: return "Query Gestures"
            case 0x0109: return "Query Wear"
            case 0x010C: return "Query ANC State"
            case 0x010F: return "Query EQ Preset"
            case 0x010D: return "Query Switch Status"
            case 0x0122: return "Query Custom EQ"
            case 0x0124: return "Query BassWave Value"
            default: return String(format: "Cmd 0x%04X", cmd16)
            }
        }

        if cmdHi == 0x84 && d.count >= 10 {
            return String(format: "Ack for cmd 0x%02X (status=%d%@)", cmdLo, Int(d[9]), d[9] == 0 ? " OK" : " ERR")
        }
        if cmdHi == 0x05 {
            if let st = decodeStatus(d) { return "Change Notification: \(st)" }
            return "Change Notification (0x05)"
        }
        if cmdHi == 0x02 && cmdLo == 0x04 {
            if d.count >= 10 && d[9] == 0xF1 {
                let side = d.count > 10 ? (d[10] == 1 ? "Left" : (d[10] == 2 ? "Right" : "")) : ""
                return "Gesture Event (\(side)): \(hex(Array(d[9...])))"
            }
            if d.count >= 14 && (Int(d[7]) | (Int(d[8]) << 8)) == 5 && d[9] == 0x03 && d[10] == 0x01 {
                let v = Int(d[12]) | (Int(d[13]) << 8)
                let desc: String
                switch v {
                case 0x0008: desc = "Off"
                case 0x0100: desc = "Transparency"
                case 0x0800: desc = "Adaptive"
                case 0x0010: desc = "ANC High"
                case 0x0020: desc = "ANC Moderate"
                case 0x0040: desc = "ANC Low"
                case 0x0080: desc = "ANC Auto"
                default: desc = String(format: "0x%04X", v)
                }
                return "Live ANC Mode: \(desc)"
            }
            if d.count >= 14 && (Int(d[7]) | (Int(d[8]) << 8)) == 5 && d[9] == 0x03 && d[10] == 0x04 {
                let v = Int(d[12]) | (Int(d[13]) << 8)
                let desc: String
                switch v {
                case 0x0010: desc = "High"
                case 0x0020: desc = "Moderate"
                case 0x0040: desc = "Low"
                default: desc = String(format: "0x%04X", v)
                }
                return "Live Auto Level: \(desc)"
            }
            return "Live Status Notification (0x0402)"
        }
        if cmdHi == 0x81 {
            switch cmdLo {
            case 0x06: return "Reply Battery"
            case 0x08: return "Reply Gestures"
            case 0x09: return "Reply Wear"
            case 0x0C: return "Reply ANC State"
            case 0x0F: return "Reply EQ Preset (\(last))"
            case 0x0D: return "Reply Switch Status"
            case 0x22: return "Reply Custom EQ"
            case 0x24: return "Reply BassWave Value (\(Int8(bitPattern: last)))"
            default: return String(format: "Reply 0x%02X81", cmdLo)
            }
        }
        if cmdHi == 0x25 && cmdLo == 0x81 { return "Reply Battery (0x8125)" }
        return String(format: "Packet 0x%04X", cmd16)
    }

    // MARK: Decoders
    static func decodeStatus(_ d: [UInt8]) -> String? {
        var level: String? = nil, onoff: String? = nil
        var i = 0
        while i + 7 <= d.count {
            defer { i += 1 }
            if d[i] != 0x05 || d[i+1] != 0x00 || d[i+2] != 0x03 { continue }
            let key = d[i+3]
            let tail = (Int(d[i+5]) << 8) | Int(d[i+6])
            let name: String
            switch tail {
            case 0x0800: name = "OFF"
            case 0x0001: name = "Transparency"
            case 0x1000: name = "ANC High"
            case 0x2000: name = "ANC Moderate"
            case 0x4000: name = "ANC Low"
            case 0x8000: name = "ANC (Auto)"
            default: name = String(format: "0x%04X", tail)
            }
            if key == 0x04 { level = "Auto → " + name }
            else if key == 0x01 { level = name }
            else if key == 0x02 { onoff = (tail == 0x0200) ? "ANC on" : "ANC off" }
        }
        return level ?? onoff
    }

    struct BatteryEntry: Equatable { let name: String; let percent: Int; let charging: Bool }

    static func decodeBattery(_ d: [UInt8]) -> [BatteryEntry]? {
        let i = indexOf(d, [0x81, 0x25])
        if i < 0 || i + 4 > d.count { return nil }
        let plen = Int(d[i+2]) | (Int(d[i+3]) << 8)
        let start = i + 4
        if start + plen > d.count || plen < 2 { return nil }
        let count = Int(d[start + 1])
        let names = ["", "Left", "Right", "Case"]
        var out: [BatteryEntry] = []
        for k in 0..<count {
            let p = start + 2 + k * 2
            if p + 1 >= d.count { break }
            let id = Int(d[p]), raw = Int(d[p+1])
            out.append(BatteryEntry(name: id < names.count ? names[id] : "id\(id)",
                                    percent: raw & 0x7F, charging: (raw & 0x80) != 0))
        }
        return out.isEmpty ? nil : out
    }

    struct EqEntry: Equatable { let id: UInt8; let name: String; let isSelected: Bool; let db: [Int] }

    static func decodeCustomEqList(_ d: [UInt8]) -> [EqEntry] {
        var result: [EqEntry] = []
        let i = indexOf(d, [0x22, 0x81, 0x00])
        if i < 0 || i + 6 > d.count { return result }
        var pos = i + 6
        if pos >= d.count { return result }
        let count = Int(d[pos]); pos += 1
        var k = 0
        while k < count && pos < d.count {
            k += 1
            if pos + 4 > d.count { break }
            let isSel = d[pos]; pos += 1
            pos += 2 // min / max
            let eqId = d[pos]; pos += 1
            if pos >= d.count { break }
            let nameLen = Int(d[pos]); pos += 1
            var name = ""
            if nameLen > 0 && pos + nameLen <= d.count {
                name = String(decoding: d[pos..<(pos + nameLen)], as: UTF8.self)
            }
            pos += nameLen
            if pos >= d.count { break }
            let freqCount = Int(d[pos]); pos += 1
            var db = [Int](repeating: 0, count: freqCount)
            for f in 0..<freqCount {
                if pos + 2 >= d.count { break }
                pos += 2
                db[f] = Int(Int8(bitPattern: d[pos])); pos += 1
            }
            result.append(EqEntry(id: eqId, name: name.isEmpty ? "Slot \(eqId)" : name,
                                  isSelected: isSel == 1, db: db))
        }
        return result
    }

    static func decodeBassWaveValue(_ d: [UInt8]) -> Int? {
        let i = indexOf(d, [0x24, 0x81])
        if i < 0 || i + 9 > d.count { return nil }
        return Int(Int8(bitPattern: d[i + 8]))
    }

    static func decodeBassWaveOn(_ d: [UInt8]) -> Bool? {
        let i = indexOf(d, [0x0D, 0x81])
        if i < 0 || i + 5 >= d.count { return nil }
        let plen = Int(d[i+3]) | (Int(d[i+4]) << 8)
        let start = i + 5
        let end = min(start + plen, d.count)
        var p = start
        while p + 1 < end {
            if d[p] == 0x1D { return d[p+1] == 1 }
            p += 1
        }
        return nil
    }

    static func decodeEqPreset(_ d: [UInt8]) -> UInt8? {
        let i = indexOf(d, [0x0F, 0x81])
        if i < 0 || i + 7 > d.count { return nil }
        return d[i + 6]
    }

    struct AncState { var off = false, trans = false, anc = false, auto = false, adaptive = false; var level = "" }

    private static func isAncMask(_ d: [UInt8], field: UInt8) -> Bool {
        d.count >= 14 && d[4] == 0x04 && d[5] == 0x02 && (Int(d[7]) | (Int(d[8]) << 8)) == 5 && d[10] == field
    }

    private static func mapAnc(_ v: Int) -> AncState? {
        switch v {
        case 0x0008: return AncState(off: true)
        case 0x0100: return AncState(trans: true)
        case 0x0800: return AncState(adaptive: true, level: "Adaptive")
        case 0x0010: return AncState(anc: true, level: "High")
        case 0x0020: return AncState(anc: true, level: "Moderate")
        case 0x0040: return AncState(anc: true, level: "Low")
        case 0x0080: return AncState(anc: true, auto: true, level: "Auto")
        default: return nil
        }
    }

    private static func levelName(_ v: Int) -> String? {
        switch v { case 0x10: return "High"; case 0x20: return "Moderate"; case 0x40: return "Low"; default: return nil }
    }

    static func decodeAncMode(_ d: [UInt8]) -> AncState? {
        guard isAncMask(d, field: 0x01) else { return nil }
        return mapAnc(Int(d[12]) | (Int(d[13]) << 8))
    }

    static func decodeAncReply(_ d: [UInt8]) -> AncState? {
        let i = indexOf(d, [0x0C, 0x81])
        if i < 0 || i + 10 > d.count || d[i+6] != 0x01 { return nil }
        return mapAnc(Int(d[i+8]) | (Int(d[i+9]) << 8))
    }

    static func decodeAncReplyAutoLevel(_ d: [UInt8]) -> String? {
        let i = indexOf(d, [0x0C, 0x81])
        if i < 0 || i + 10 > d.count || d[i+6] != 0x04 { return nil }
        return levelName(Int(d[i+8]) | (Int(d[i+9]) << 8))
    }

    static func decodeAncAutoLevel(_ d: [UInt8]) -> String? {
        guard isAncMask(d, field: 0x04) else { return nil }
        return levelName(Int(d[12]) | (Int(d[13]) << 8))
    }

    struct WearState { let bothInCase: Bool; let anyInEar: Bool }

    private static func fromFlags(_ l: UInt8, _ r: UInt8) -> WearState {
        WearState(bothInCase: (l & 1) == 0 && (r & 1) == 0, anyInEar: (l & 2) != 0 || (r & 2) != 0)
    }

    static func decodeWear(_ d: [UInt8]) -> WearState? {
        let i = indexOf(d, [0x09, 0x81])
        if i >= 0 && i + 11 <= d.count { return fromFlags(d[i+8], d[i+10]) }
        if d.count >= 17 && d[4] == 0x04 && d[5] == 0x02
            && (Int(d[7]) | (Int(d[8]) << 8)) == 8 && d[9] == 0x02 {
            return fromFlags(d[12], d[14])
        }
        return nil
    }

    struct GestureEntry { let side: UInt8, category: UInt8, gesture: UInt8, action: UInt8 }

    static func decodeGestures(_ d: [UInt8]) -> [GestureEntry] {
        var list: [GestureEntry] = []
        let i = indexOf(d, [0x08, 0x81])
        if i < 0 || i + 7 > d.count { return list }
        let count = Int(d[i + 6])
        let start = i + 7
        for k in 0..<count {
            let p = start + k * 4
            if p + 3 >= d.count { break }
            list.append(GestureEntry(side: d[p], category: d[p+1], gesture: d[p+2], action: d[p+3]))
        }
        return list
    }

    /// Splits a byte stream into AA-framed packets: [0xAA][len][len bytes].
    static func extractFrames(_ acc: inout [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        while true {
            while let f = acc.first, f != 0xAA { acc.removeFirst() }
            if acc.count < 2 { break }
            let total = Int(acc[1]) + 2
            if acc.count < total { break }
            frames.append(Array(acc[0..<total]))
            acc.removeFirst(total)
        }
        return frames
    }
}
