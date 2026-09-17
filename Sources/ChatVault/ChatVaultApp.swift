import SwiftUI

@main
struct ChatVaultApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label("ChatVault", systemImage: "bubble.left.and.bubble.right")
        }
        .menuBarExtraStyle(.window)
    }
}
