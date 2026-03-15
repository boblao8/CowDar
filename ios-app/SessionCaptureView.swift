import SwiftUI
import UIKit

// Steps in the capture flow
enum CaptureStep: Int, CaseIterable {
    case scan    = 0
    case details = 1
    case summary = 2

    var title: String {
        switch self {
        case .scan:    return "LiDAR Capture"
        case .details: return "Details"
        case .summary: return "Summary"
        }
    }

    var icon: String {
        switch self {
        case .scan:    return "wave.3.forward"
        case .details: return "list.bullet.clipboard"
        case .summary: return "checkmark.seal.fill"
        }
    }
}

struct SessionCaptureView: View {
    @ObservedObject var session: AnimalSession
    let onComplete: () -> Void

    @State private var currentStep: CaptureStep = .scan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                stepProgress

                stepContent
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        )
                    )
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.callout.bold())
                    Text("Close")
                        .font(.callout)
                }
                .foregroundColor(.gray)
            }

            Spacer()

            Text("Animal \(session.sessionNumber)")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            if session.hasScan {
                Button(action: shareSession) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.cyan)
                }
            } else {
                Color.clear.frame(width: 44, height: 20)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 12)
    }

    // MARK: - Step progress

    private var stepProgress: some View {
        HStack(spacing: 0) {
            ForEach(CaptureStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(stepColor(step))
                            .frame(width: 32, height: 32)

                        Image(systemName: step.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(step.rawValue <= currentStep.rawValue ? .black : .gray)
                    }

                    if step != .summary {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.cyan : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func stepColor(_ step: CaptureStep) -> Color {
        if step.rawValue <= currentStep.rawValue { return .cyan }
        return Color.gray.opacity(0.25)
    }

    // MARK: - Step router

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .scan:
            ScanStepView(session: session) {
                withAnimation { currentStep = .details }
            }

        case .details:
            DetailsStepView(session: session) {
                withAnimation { currentStep = .summary }
            }

        case .summary:
            SummaryStepView(session: session) {
                session.save()
                onComplete()
                dismiss()
            }
        }
    }

    // MARK: - Share

    private func shareSession() {
        let folder = AnimalSession.sessionFolder(for: session)
        var urls: [URL] = []

        if let rgb = session.rgbCaptureFilename {
            let url = folder.appendingPathComponent(rgb)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }

        if let depth = session.depthCaptureFilename {
            let url = folder.appendingPathComponent(depth)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }

        if let meta = session.captureMetadataFilename {
            let url = folder.appendingPathComponent(meta)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }
        
        if let ply = session.plyFilename {
            let url = folder.appendingPathComponent(ply)
            if FileManager.default.fileExists(atPath: url.path) {
                urls.append(url)
            }
        }

        let jsonURL = AnimalSession.sessionsDirectory().appendingPathComponent("\(session.id).json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            urls.append(jsonURL)
        }

        guard !urls.isEmpty else { return }

        let av = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let vc = windowScene.windows.first?.rootViewController {
            vc.present(av, animated: true)
        }
    }
}
