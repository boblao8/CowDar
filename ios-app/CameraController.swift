import SwiftUI
import AVFoundation

struct CameraControllerRepresentable: UIViewControllerRepresentable {
    @Binding var capturedImage: CapturedPayload?
    @Binding var captureTrigger: Bool
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        if captureTrigger {
            DispatchQueue.main.async {
                self.captureTrigger = false
                uiViewController.capturePhoto()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraControllerRepresentable
        
        init(_ parent: CameraControllerRepresentable) {
            self.parent = parent
        }
        
        func didCapturePhoto(payload: CapturedPayload) {
            DispatchQueue.main.async {
                self.parent.capturedImage = payload
            }
        }
    }
}