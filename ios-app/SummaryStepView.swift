import SwiftUI
import UIKit

struct SummaryStepView: View {
    @ObservedObject var session: AnimalSession
    let onDone: () -> Void

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.cyan)

                Text("Animal \(session.sessionNumber) Recorded")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text(session.displayName)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 12) {
                    completionCard
                    detailsCard
                    serverResponseCard
                    shareCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            Spacer()

            Button(action: onDone) {
                Label("Done — Next Animal", systemImage: "plus.circle")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.cyan)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    private var completionCard: some View {
        VStack(spacing: 0) {
            checkRow(
                label: "RGB + Depth Capture",
                done: session.hasScan,
                detail: session.hasScan ? "Captured" : "Skipped",
                color: .cyan
            )

            Divider().background(Color.white.opacity(0.08))

            checkRow(
                label: "Known Weight",
                done: session.hasWeight,
                detail: session.hasWeight ? "\(Int(session.knownWeightKg!)) kg" : "Not recorded",
                color: .orange
            )
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func checkRow(label: String, done: Bool, detail: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundColor(done ? color : .gray.opacity(0.4))

            Text(label)
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var detailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Breed", session.breed.rawValue)
            Divider().background(Color.white.opacity(0.08))
            detailRow("Sex", session.sex.rawValue)
            Divider().background(Color.white.opacity(0.08))
            detailRow("Location", session.location.rawValue)

            if !session.notes.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                detailRow("Notes", session.notes)
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Server response card

    private var serverResponseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weight Estimate", systemImage: "scalemass.fill")
                .font(.subheadline.bold())
                .foregroundColor(.orange)

            serverResponseBody
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2)))
    }

    @ViewBuilder
    private var serverResponseBody: some View {
        switch session.weightEstimateState {
        case .notRequested:
            Text("No request sent")
                .font(.caption)
                .foregroundColor(.gray)

        case .waiting:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.orange)
                    .scaleEffect(0.85)
                Text("Still Waiting For Response")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

        case .received:
            if let kg = session.parsedPredictedWeight {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(Int(kg.rounded()))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                    Text("kg")
                        .font(.title3.bold())
                        .foregroundColor(.orange.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Label("Received — no weight in response", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

        case .failed:
            Label("Server couldn't parse data", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Share Files", systemImage: "square.and.arrow.up")
                .font(.subheadline.bold())
                .foregroundColor(.cyan)

            Text("Share the RGB image, depth capture, and metadata for desktop processing.")
                .font(.caption)
                .foregroundColor(.gray)

            Button(action: prepareAndShare) {
                Label("Share Capture Files", systemImage: "airplayvideo")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.cyan.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.cyan.opacity(0.05))
        .cornerRadius(14)
    }

    private func prepareAndShare() {
        let folder = AnimalSession.sessionFolder(for: session)
        var items: [Any] = []

        if let rgb = session.rgbCaptureFilename {
            let url = folder.appendingPathComponent(rgb)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }

        if let depth = session.depthCaptureFilename {
            let url = folder.appendingPathComponent(depth)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }

        if let meta = session.captureMetadataFilename {
            let url = folder.appendingPathComponent(meta)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }
        if let ply = session.plyFilename {
            let url = folder.appendingPathComponent(ply)
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }

        let jsonURL = AnimalSession.sessionsDirectory().appendingPathComponent("\(session.id).json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            items.append(jsonURL)
        }

        if items.isEmpty {
            let summary = """
            CattleScan — Animal \(session.sessionNumber)
            Breed: \(session.breed.rawValue)
            Sex: \(session.sex.rawValue)
            Location: \(session.location.rawValue)
            Weight: \(session.hasWeight ? "\(Int(session.knownWeightKg!)) kg" : "Not recorded")
            Notes: \(session.notes.isEmpty ? "None" : session.notes)
            """
            items.append(summary)
        }

        shareItems = items
        showShareSheet = true
    }
}
