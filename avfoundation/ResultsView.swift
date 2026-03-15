import SwiftUI

struct ResultsView: View {
    @ObservedObject var viewModel: CameraViewModel
    let payload: CapturedPayload

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // No NavigationStack here — this view is pushed onto CameraView's NavigationStack.
        VStack {
            if viewModel.isLoading {
                ProgressView("Predicting...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let result = viewModel.predictionResult {
                Form {
                    Section("Prediction Results") {
                        ResultRow(label: "Success",                value: result.success ? "Yes" : "No")
                        ResultRow(label: "Predicted Weight",       value: String(format: "%.2f kg", result.predictedWeight))
                        ResultRow(label: "Distance P2 to P10",     value: String(format: "%.4f m", result.distPoint2To10))
                        ResultRow(label: "Distance Midpoint to P3",value: String(format: "%.4f m", result.distMidpointTo3))
                    }
                }

            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                Text("Ready to submit.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button("Capture Another") {
                viewModel.reset()   // clears capturedPayload, result, error
                dismiss()           // pops back to CameraView
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fire the network request automatically when this view first appears.
            if viewModel.predictionResult == nil && viewModel.errorMessage == nil {
                await viewModel.submitPayload(payload)
            }
        }
    }
}
