import Foundation

/// State shared between the app and the WidgetKit extension through a JSON file.
/// (The sandboxed extension reads this folder via a temporary-exception entitlement.)
struct WidgetBattery: Codable, Equatable {
    var name: String
    var percent: Int
    var charging: Bool
}

struct WidgetSnapshot: Codable, Equatable {
    var ready = false
    var title = "OnePlus Buds"
    var isPro3 = false
    var battery: [WidgetBattery] = []
    var mode = "none"          // anc | adaptive | trans | off | none
    var level = ""             // High / Moderate / Low / Auto
    var worn = -1              // -1 unknown, 0 not worn, 1 worn
    var lang = "en"
    var updated = Date()

    static let sample = WidgetSnapshot(
        ready: true, title: "OnePlus Buds 4", isPro3: false,
        battery: [WidgetBattery(name: "Left", percent: 80, charging: false),
                  WidgetBattery(name: "Right", percent: 78, charging: false),
                  WidgetBattery(name: "Case", percent: 64, charging: true)],
        mode: "anc", level: "Auto", worn: 1, lang: "en", updated: Date())
}

enum WidgetIO {
    static let dir = URL(fileURLWithPath: "/Users/Shared/OnePlusBuds", isDirectory: true)
    static var stateURL: URL { dir.appendingPathComponent("state.json") }
    static var commandURL: URL { dir.appendingPathComponent("command.txt") }

    static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ s: WidgetSnapshot) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o777])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(s) { try? d.write(to: stateURL, options: .atomic) }
    }
}
