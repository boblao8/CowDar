import Foundation

struct APIClient {
    func predictWeight(payload: CapturedPayload) async throws -> PredictionResponse {
        let url = URL(string: "https://unintent-neida-pendanted.ngrok-free.dev/api/av")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")

        var body = Data()

        // Helper — avoids repeating boundary/CRLF boilerplate.
        func appendFile(name: String, filename: String, contentType: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        func appendText(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        // Fields appended in the exact order the server expects.
        // (Using a dict would give undefined iteration order.)
        appendFile(name: "photo",      filename: "capture.jpg",  contentType: "image/jpeg",               data: payload.photoData)
        appendFile(name: "bin",        filename: "depth.bin",    contentType: "application/octet-stream",  data: payload.depthData)
        appendText(name: "depthX",      value: "\(payload.depthWidth)")
        appendText(name: "depthY",      value: "\(payload.depthHeight)")
        appendText(name: "referenceWidth",  value: "\(payload.referenceWidth)")
        appendText(name: "referenceHeight", value: "\(payload.referenceHeight)")
        appendText(name: "intrinsics",  value: payload.intrinsicsString)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        print("[api] Multipart body assembled — total bytes: \(body.count)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError("Invalid HTTP response.")
        }

        if httpResponse.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw AppError.backendError("Backend error \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(PredictionResponse.self, from: data)
    }
}
