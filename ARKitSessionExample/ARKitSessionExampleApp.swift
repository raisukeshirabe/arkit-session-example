import SwiftUI

@main
@MainActor
struct ARKitSessionExampleApp: App {
    @State private var model = ViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        ImmersiveSpace(id: "ImmersiveSpace") {
            ImmersiveView()
                .environment(model)
        }
    }
}
