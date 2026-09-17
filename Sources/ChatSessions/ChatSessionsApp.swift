import SwiftUI

@main
struct ChatSessionsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label("Chat Sessions", systemImage: "bubble.left.and.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}
