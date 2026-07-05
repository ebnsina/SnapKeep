import SwiftUI

@main
struct SnapKeepApp: App {
    @State private var app = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(app)
                .onAppear { app.refreshAuthorization() }
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.window)
    }
}
