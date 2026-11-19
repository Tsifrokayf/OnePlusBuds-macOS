import SwiftUI

struct LogView: View {
    @EnvironmentObject var m: AppModel
    @State private var hex = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(trf("Packets: %d", m.packetCount)).font(.system(size: 12)).foregroundColor(.textLo)
                Spacer()
                Toggle(tr("Auto-scroll"), isOn: $m.autoScroll).toggleStyle(.checkbox)
                Button(tr("Probe features")) { m.probeFeatures() }.disabled(!m.ready || m.probing)
                Button(tr("Copy all")) { m.copyLog() }
                Button(tr("Clear")) { m.clearLog() }
            }
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(m.logLines) { l in
                            Text(l.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(l.text.contains("[SEND]") ? Color.accent : .textHi)
                                .textSelection(.enabled)
                                .id(l.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color.card)
                .cornerRadius(8)
                .onChange(of: m.logLines.count) { _ in
                    if m.autoScroll, let last = m.logLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            HStack {
                TextField("AA 07 00 00 06 01 25 00 00", text: $hex)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(tr("Send hex"), action: send)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundColor(.red) }
        }
        .padding(12)
        .background(Color.bg)
        .frame(minWidth: 640, minHeight: 360)
        .preferredColorScheme(.dark)
    }

    private func send() { error = m.sendHex(hex) }
}
