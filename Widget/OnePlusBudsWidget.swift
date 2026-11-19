import WidgetKit
import SwiftUI

private let ruW: [String: String] = [
    "Left": "Левый", "Right": "Правый", "Case": "Кейс",
    "Noise Cancellation": "Шумоподавление", "Adaptive": "Адаптивный", "Transparency": "Прозрачность", "Off": "Выкл",
    "Not connected": "Не подключено", "Open the app": "Откройте приложение", "In ear": "В ушах", "Out of ear": "Не в ушах",
    "ANC": "Шумодав", "Trans": "Прозр.", "Auto": "Авто", "High": "Высокий", "Moderate": "Средний", "Low": "Низкий"
]
private func L(_ s: String, _ lang: String) -> String { lang == "ru" ? (ruW[s] ?? s) : s }

struct Entry: TimelineEntry { let date: Date; let snap: WidgetSnapshot }

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snap: context.isPreview ? .sample : (WidgetIO.load() ?? .sample)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let s = WidgetIO.load() ?? WidgetSnapshot()
        completion(Timeline(entries: [Entry(date: Date(), snap: s)], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct Ring: View {
    let label: String; let pct: Int; let charging: Bool; var size: CGFloat = 46
    private var tint: Color { pct < 0 ? .gray : (pct <= 20 ? .red : (charging ? .green : .primary)) }
    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle().stroke(.primary.opacity(0.15), lineWidth: 5)
                Circle().trim(from: 0, to: pct < 0 ? 0 : CGFloat(pct) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                Text(pct < 0 ? "–" : "\(pct)").font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            }
            .frame(width: size, height: size)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        }
    }
}

struct ModeButton: View {
    let id: String; let icon: String; let title: String; let active: Bool; var compact = false
    var body: some View {
        Link(destination: URL(string: "oneplusbuds://mode/\(id)")!) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: compact ? 14 : 17, weight: .semibold))
                if !compact { Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 28 : 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.1)))
            .foregroundStyle(active ? Color.white : Color.primary)
        }
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry
    var s: WidgetSnapshot { e.snap }
    var lang: String { s.lang }
    func bat(_ n: String) -> WidgetBattery? { s.battery.first { $0.name.lowercased().hasPrefix(n) } }

    var modes: [(String, String, String)] {
        var m = [("anc", "waveform.path.ecg", L("ANC", lang))]
        if !s.isPro3 { m.append(("adaptive", "sparkles", L("Adaptive", lang))) }
        m += [("trans", "ear.and.waveform", L("Trans", lang)), ("off", "ear", L("Off", lang))]
        return m
    }
    var modeTitle: String {
        switch s.mode {
        case "anc": return L("Noise Cancellation", lang) + (s.level.isEmpty ? "" : " · " + L(s.level, lang))
        case "adaptive": return L("Adaptive", lang)
        case "trans": return L("Transparency", lang)
        case "off": return L("Off", lang)
        default: return "—"
        }
    }

    var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "earbuds").foregroundStyle(s.ready ? Color.accentColor : .gray)
            Text(s.title).font(.caption.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if s.worn >= 0 && s.ready && family != .systemSmall {
                Text(L(s.worn == 1 ? "In ear" : "Out of ear", lang)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    var rings: some View {
        HStack(spacing: family == .systemSmall ? 8 : 14) {
            Ring(label: L("Left", lang), pct: bat("l")?.percent ?? -1, charging: bat("l")?.charging ?? false, size: family == .systemSmall ? 40 : 52)
            Ring(label: L("Right", lang), pct: bat("r")?.percent ?? -1, charging: bat("r")?.charging ?? false, size: family == .systemSmall ? 40 : 52)
            Ring(label: L("Case", lang), pct: bat("c")?.percent ?? -1, charging: bat("c")?.charging ?? false, size: family == .systemSmall ? 40 : 52)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !s.ready && s.battery.isEmpty {
                Spacer()
                Text(L("Not connected", lang)).font(.callout).foregroundStyle(.secondary)
                Text(L("Open the app", lang)).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
            } else {
                switch family {
                case .systemSmall:
                    Spacer(minLength: 0)
                    rings
                    Text(modeTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                case .systemMedium:
                    HStack(alignment: .center, spacing: 14) {
                        rings
                        VStack(spacing: 6) {
                            Text(modeTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 5) { ForEach(modes, id: \.0) { ModeButton(id: $0.0, icon: $0.1, title: $0.2, active: s.mode == $0.0, compact: true) } }
                        }
                    }
                default:
                    Spacer(minLength: 0)
                    HStack { Spacer(); rings; Spacer() }
                    Divider()
                    Text(modeTitle).font(.subheadline.weight(.medium))
                    HStack(spacing: 6) { ForEach(modes, id: \.0) { ModeButton(id: $0.0, icon: $0.1, title: $0.2, active: s.mode == $0.0) } }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(2)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct OnePlusBudsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OnePlusBudsWidget", provider: Provider()) { entry in
            WidgetView(e: entry)
        }
        .configurationDisplayName("OnePlus Buds")
        .description("Battery and noise control / Заряд и шумоподавление")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct OnePlusBudsWidgetBundle: WidgetBundle {
    var body: some Widget { OnePlusBudsWidget() }
}
