
import SwiftUI

// MARK: - API Response Codable Struct
struct PredictionResponse: Codable {
    let success: Bool
    let predictedWeight: Double
    let distPoint2To10: Double
    let distMidpointTo3: Double
}

// MARK: - ContentView
struct ContentView: View {
    @State private var plyUrlString: String = "https://example.com/cow.ply" // Placeholder
    @State private var imageUrlString: String = "https://example.com/cow.jpg" // Placeholder
    @State private var isLoading: Bool = false
    @State private var predictionResult: PredictionResponse?
    @State private var errorMessage: String?

    private let backendEndpoint = URL(string: "https://unintent-neida-pendanted.ngrok-free.dev/api/tim/dist")!

    var body: some View {
        NavigationView {
            Form {
                Section("Input URLs") {
                    TextField("PLY File URL", text: $plyUrlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("Image File URL", text: $imageUrlString)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section {
                    Button("Predict Weight") {
                        Task {
                            await predictWeight()
                        }
                    }
                    .disabled(isLoading)
                }

                if isLoading {
                    ProgressView("Predicting...")
                }

                if let predictionResult = predictionResult {
                    Section("Prediction Results") {
                        ResultRow(label: "Success", value: predictionResult.success ? "Yes" : "No")
                        ResultRow(label: "Predicted Weight", value: String(format: "%.2f kg", predictionResult.predictedWeight))
                        ResultRow(label: "Distance P2 to P10", value: String(format: "%.4f m", predictionResult.distPoint2To10))
                        ResultRow(label: "Distance Midpoint to P3", value: String(format: "%.4f m", predictionResult.distMidpointTo3))
                    }
                }

                if let errorMessage = errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Cow Weight Predictor")
        }
    }

    // MARK: - Network Logic
    private func predictWeight() async {
        isLoading = true
        errorMessage = nil
        predictionResult = nil

        do {
            guard let plyURL = URL(string: plyUrlString),
                  let imageURL = URL(string: imageUrlString) else {
                throw AppError.invalidURL
            }

            // Step A: Download files
            let plyData = try await downloadFile(from: plyURL)
            let imageData = try await downloadFile(from: imageURL)

            // Step B: Multipart Upload
            let request = try createMultipartRequest(plyData: plyData, imageData: imageData)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.networkError("Invalid HTTP response.")
            }

            if httpResponse.statusCode != 200 {
                let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
                throw AppError.backendError("Backend error \(httpResponse.statusCode): \(responseBody)")
            }

            // Step C: Decode response
            let decoder = JSONDecoder()
            // res using camelCase // decoder.keyDecodingStrategy = .convertFromSnakeCase // To handle predictedWeight -> predicted_weight
            let result = try decoder.decode(PredictionResponse.self, from: data)
            predictionResult = result

        } catch {
            errorMessage = handleError(error)
        }
        isLoading = false
    }

    private func downloadFile(from url: URL) async throws -> Data {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            throw AppError.downloadError("Failed to download file from \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func createMultipartRequest(plyData: Data, imageData: Data) throws -> URLRequest {
        var request = URLRequest(url: backendEndpoint)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        var body = Data()

// Append PLY file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"ply\"; filename=\"cow.ply\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(plyData)
        body.append("\r\n".data(using: .utf8)!)

        // Append Image file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"cow.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return request
    }

    private func handleError(_ error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        } else {
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - Helper Views
struct ResultRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Custom Error Types
enum AppError: LocalizedError {
    case invalidURL
    case downloadError(String)
    case networkError(String)
    case backendError(String)
    case decodingError(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "One or both of the provided URLs are invalid."
        case .downloadError(let message):
            return "Download error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .backendError(let message):
            return "Backend error: \(message)"
        case .decodingError(let message):
            return "Data decoding error: \(message)"
        case .unknown:
            return "An unknown error occurred."
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
