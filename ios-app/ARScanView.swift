import SwiftUI
import ARKit
import RealityKit

struct ARScanView: UIViewRepresentable {
    @ObservedObject var viewModel: ScanViewModel

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.session.delegate = context.coordinator

        viewModel.arSession = arView.session
        viewModel.configureForTargeting(session: arView.session)

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        uiView.debugOptions = []
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let viewModel: ScanViewModel

        init(viewModel: ScanViewModel) {
            self.viewModel = viewModel
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            viewModel.updateTargeting(frame: frame)

            if viewModel.state == .burstCapturing {
                viewModel.processFrame(frame)
            }
        }
    }
}
