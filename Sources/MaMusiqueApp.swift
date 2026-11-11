import SwiftUI

@main
struct MaMusiqueApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var player = PlayerController()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(player)
                .tint(.red)
                .onAppear { library.restore() }
                .onChange(of: phase) { _, p in
                    if p == .active { library.rescan() }
                }
        }
    }
}
