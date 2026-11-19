import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make sure the Dock / app switcher always show our icon, even if LaunchServices has a stale cache.
        if let img = Bundle.main.image(forResource: "AppIcon")
            ?? Bundle.main.path(forResource: "icon", ofType: "png").flatMap({ NSImage(contentsOfFile: $0) }) {
            NSApp.applicationIconImage = img
        }
        // When started as a login item, stay in the menu bar without showing the window.
        let e = NSAppleEventManager.shared().currentAppleEvent
        let asLoginItem = e?.eventID == AEEventID(kAEOpenApplication)
            && e?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if asLoginItem || CommandLine.arguments.contains("--minimized") {
            DispatchQueue.main.async { NSApp.windows.forEach { $0.close() } }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { AppModel.shared?.handleURL($0) }
    }
}

@main
struct OnePlusBudsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("OnePlus Buds", id: "main") {
            ContentView().environmentObject(model)
        }
        .defaultSize(width: 480, height: 780)

        Window("Packet Log", id: "log") {
            LogView().environmentObject(model)
        }

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            Image(systemName: "earbuds")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(m.title)
        Text(m.ready ? (m.batterySummary.isEmpty ? tr("Connected") : m.batterySummary) : tr("Not connected"))
        Divider()
        Button(tr("Show")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Toggle(tr("Liquid Glass"), isOn: $m.liquidGlass)
        Toggle(tr("Connect popup"), isOn: $m.showPopup)
        Toggle(tr("Start at login"), isOn: Binding(get: { m.startAtLogin }, set: { m.setStartAtLogin($0) }))
        Divider()
        Button(tr("Quit")) {
            m.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
