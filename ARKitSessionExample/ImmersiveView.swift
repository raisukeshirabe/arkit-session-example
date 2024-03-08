import ARKit
import RealityKit
import SwiftUI

struct ImmersiveView: View {
    @Environment(ViewModel.self) var model
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @Environment(\.openWindow) var openWindow

    var body: some View {
        RealityView { content in
            content.add(model.setupContentEntity())
        }
        .task {
            do {
                if model.dataProvidersAreSupported && model.isReadyToRun {
                    try await model.session.run([model.sceneReconstruction, model.handTracking])
                } else {
                    await dismissImmersiveSpace()
                }
            } catch {
                print("Failed to start session: \(error)")
                await dismissImmersiveSpace()
                openWindow(id: "error")
            }
        }
        .task {
            await model.processHandUpdates()
        }
        .task(priority: .low) {
            await model.processReconstructionUpdates()
        }
        .task {
            await model.monitorSessionEvents()
        }
        .onChange(of: model.errorState) {
            openWindow(id: "error")
        }
    }
}
