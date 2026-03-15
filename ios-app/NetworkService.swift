import Foundation

/// Sends the four scan files to the backend and updates the session's
/// `weightEstimateState` / `weightEstimateJSON` properties on the main actor.
///
/// The request is fire-and-forget: the detached Task keeps running even if
/// the presenting view is dismissed.
final class NetworkService {

    static let shared = NetworkService()
    private init() {}

    private let endpointURL = URL(
        string: "https://unintent-neida-pendanted.ngrok-free.dev/api/reef/dist"
    )!

    // MARK: - Public

    func submitScanForWeightEstimate(_ session: AnimalSession) {
        // Always resolve to the canonical (store-registered) instance so that
        // @Published mutations are seen by any live @ObservedObject observer.
        let canonical = SessionStore.shared.session(withID: session.id) ?? session
        if canonical !== session {
            print("[NetworkService] ⚠ Resolved to canonical instance (was a different object)")
        }
        _submit(canonical)
    }

    private func _submit(_ session: AnimalSession) {
        print("[NetworkService] ▶︎ submitScanForWeightEstimate called for session \(session.id)")
        print("[NetworkService]   sessionNumber : \(session.sessionNumber)")
        print("[NetworkService]   endpoint      : \(endpointURL.absoluteString)")

        // Immediately flip to .waiting so both Summary and Detail views react
        Task { @MainActor in
            session.weightEstimateState = .waiting
            session.weightEstimateJSON  = nil
            session.save()
            print("[NetworkService] ✔ State set to .waiting on main actor")
        }

        // Background work — independent of view lifecycle
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.performRequest(for: session)
        }
    }

    // MARK: - Private

    private func performRequest(for session: AnimalSession) async {
        print("[NetworkService] ── performRequest start ──────────────────────────")

        let folder = AnimalSession.sessionFolder(for: session)
        print("[NetworkService]   session folder : \(folder.path)")

        // ── Verify file names are set ────────────────────────────────────────
        guard
            let rgbName = session.rgbCaptureFilename,
            let plyName = session.plyFilename
        else {
            print("[NetworkService] ✖ Missing filename(s):")
            print("                   rgb = \(session.rgbCaptureFilename ?? "nil")")
            print("                   ply = \(session.plyFilename ?? "nil")")
            await fail(session)
            return
        }

        let rgbURL = folder.appendingPathComponent(rgbName)
        let plyURL = folder.appendingPathComponent(plyName)

        // ── Verify files exist on disk ───────────────────────────────────────
        let fm = FileManager.default
        print("[NetworkService]   rgb exists=\(fm.fileExists(atPath: rgbURL.path))  path=\(rgbURL.path)")
        print("[NetworkService]   ply exists=\(fm.fileExists(atPath: plyURL.path))  path=\(plyURL.path)")

        guard fm.fileExists(atPath: rgbURL.path),
              fm.fileExists(atPath: plyURL.path) else {
            print("[NetworkService] ✖ One or more required files missing from disk — aborting")
            await fail(session)
            return
        }

        // ── Build multipart body ─────────────────────────────────────────────
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func appendFile(fieldName: String, fileURL: URL, mimeType: String) {
            guard let fileData = try? Data(contentsOf: fileURL) else {
                print("[NetworkService] ⚠ Could not read file for field '\(fieldName)': \(fileURL.path)")
                return
            }
            print("[NetworkService]   appending '\(fieldName)' — \(fileData.count) bytes (\(fileURL.lastPathComponent))")
            body.append("--\(boundary)\r\n")
            body.append(
                "Content-Disposition: form-data; name=\"\(fieldName)\"; " +
                "filename=\"\(fileURL.lastPathComponent)\"\r\n"
            )
            body.append("Content-Type: \(mimeType)\r\n\r\n")
            body.append(fileData)
            body.append("\r\n")
        }

        appendFile(fieldName: "image", fileURL: rgbURL, mimeType: "image/jpeg")
        appendFile(fieldName: "ply",   fileURL: plyURL, mimeType: "application/octet-stream")
        body.append("--\(boundary)--\r\n")

        print("[NetworkService]   total body size : \(body.count) bytes")

        // ── Build URLRequest ─────────────────────────────────────────────────
        var request = URLRequest(url: endpointURL)
        request.httpMethod      = "POST"
        request.httpBody        = body
        request.timeoutInterval = 30
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        // Required to bypass the ngrok browser-warning interstitial page
        request.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")

        print("[NetworkService]   request headers:")
        request.allHTTPHeaderFields?.forEach { k, v in
            print("                   \(k): \(v)")
        }
        print("[NetworkService] ▶︎ firing URLSession.data(for:) …")

        // ── Execute ──────────────────────────────────────────────────────────
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                print("[NetworkService]   HTTP status : \(http.statusCode)")
                print("[NetworkService]   response headers:")
                http.allHeaderFields.forEach { k, v in
                    print("                   \(k): \(v)")
                }
            } else {
                print("[NetworkService] ⚠ Response is not HTTPURLResponse: \(type(of: response))")
            }

            let rawBody = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            print("[NetworkService]   raw response body:\n\(rawBody)")

            guard
                let http = response as? HTTPURLResponse,
                http.statusCode == 200
            else {
                print("[NetworkService] ✖ Non-200 status — marking failed")
                await fail(session)
                return
            }

            // Pretty-print for display
            if
                let obj    = try? JSONSerialization.jsonObject(with: data),
                let pretty = try? JSONSerialization.data(
                    withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
                ),
                let str = String(data: pretty, encoding: .utf8)
            {
                print("[NetworkService] ✔ JSON parsed successfully (\(str.count) chars)")
                await succeed(session, json: str)
            } else if let str = String(data: data, encoding: .utf8) {
                print("[NetworkService] ⚠ Could not parse as JSON — storing raw string")
                await succeed(session, json: str)
            } else {
                print("[NetworkService] ✖ Response data unreadable — marking failed")
                await fail(session)
            }

        } catch let urlError as URLError {
            print("[NetworkService] ✖ URLError code=\(urlError.code.rawValue) : \(urlError.localizedDescription)")
            print("[NetworkService]   failingURL : \(urlError.failingURL?.absoluteString ?? "nil")")
            await fail(session)
        } catch {
            print("[NetworkService] ✖ Unexpected error: \(error)")
            await fail(session)
        }

        print("[NetworkService] ── performRequest end ────────────────────────────")
    }

    // MARK: - Main-actor updates

    @MainActor
    private func succeed(_ session: AnimalSession, json: String) {
        print("[NetworkService] ✔ succeed() — updating session on main actor")
        session.weightEstimateState = .received
        session.weightEstimateJSON  = json
        session.save()
    }

    @MainActor
    private func fail(_ session: AnimalSession) {
        print("[NetworkService] ✖ fail() — updating session on main actor")
        session.weightEstimateState = .failed
        session.weightEstimateJSON  = nil
        session.save()
    }
}

// MARK: - Data convenience

private extension Data {
    mutating func append(_ string: String) {
        if let encoded = string.data(using: .utf8) {
            append(encoded)
        }
    }
}
