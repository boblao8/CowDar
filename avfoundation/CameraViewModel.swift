import SwiftUI
import Combine

class CameraViewModel: ObservableObject {
    @Published var capturedPayload: CapturedPayload?
    @Published var predictionResult: PredictionResponse?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false

    private let apiClient = APIClient()

    func submitPayload(_ payload: CapturedPayload) async {
        isLoading = true
        errorMessage = nil
        predictionResult = nil

        do {
            let result = try await apiClient.predictWeight(payload: payload)
            predictionResult = result
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func reset() {
        capturedPayload = nil
        predictionResult = nil
        errorMessage = nil
        isLoading = false
    }
}