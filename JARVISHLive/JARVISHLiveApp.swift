import SwiftUI

@main
struct JARVISHLiveApp: App {
    @State private var diagnostics = NetworkDiagnostics()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(diagnostics: diagnostics)
                .tint(.teal)
                .task { diagnostics.startMonitoring() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { diagnostics.stop() }
                    if phase == .active { diagnostics.startMonitoring() }
                }
        }
    }
}
