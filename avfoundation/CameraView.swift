import SwiftUI
import AVFoundation

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var showingDebugSheet = false
    @State private var triggerCapture = false
    @State private var showResults = false

    private var cameraUnavailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) == nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if cameraUnavailable {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("Camera unavailable on this device")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CameraControllerRepresentable(
                        capturedImage: $viewModel.capturedPayload,
                        captureTrigger: $triggerCapture
                    )
                    .ignoresSafeArea()
                }

                Button(action: { triggerCapture = true }) {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .background(Circle().fill(Color.blue))
                        .frame(width: 80, height: 80)
                }
                .padding(.bottom, 30)
                .disabled(cameraUnavailable)
            }
            .navigationTitle("Cowdar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Debug") { showingDebugSheet = true }
                }
            }
            .sheet(isPresented: $showingDebugSheet) {
                ContentView()
            }
            // Push ResultsView onto the stack when a payload is ready.
            .onChange(of: viewModel.capturedPayload) { newPayload in
                if newPayload != nil { showResults = true }
            }
            .navigationDestination(isPresented: $showResults) {
                if let payload = viewModel.capturedPayload {
                    ResultsView(viewModel: viewModel, payload: payload)
                } else {
                    EmptyView() // or just ResultsView(...) since the guard is already in .onChange
                }
            }
        }
    }
}
