import SwiftUI

@main
struct ChatWingApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var pip = PiPController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(pip)
                .tint(Color(red:0.0, green:0.50, blue:0.48))
                .onChange(of:scenePhase) { _, phase in
                    let foreground = phase != .background
                    try? SharedStore.shared.write(AppPresence(foreground:foreground), to:"presence.json")
                    pip.setForeground(foreground)
                    if phase == .active { model.refresh() }
                }
        }
    }
}
