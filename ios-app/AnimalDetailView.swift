import SwiftUI
import UIKit

struct AnimalDetailView: View {
    @ObservedObject var session: AnimalSession
    let onUpdate: () -> Void

    @State private var isEditing = false
    @State private var sharePayload: SharePayload?
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(spacing: 16) {
                        statusHeader
                        capturePreviewCard

                        if isEditing {
                            EditDetailsCard(session: session)
                        } else {
                            viewDetailsCard
                        }

                        weightEstimateCard
                        actionsCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            session.refreshCaptureFilenamesFromDiskIfNeeded()
            session.save()
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .alert("Delete Animal \(session.sessionNumber)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the RGB image, depth capture, metadata, PLY, and all data for this animal.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(.cyan)
            }

            Spacer()

            Text("Animal \(session.sessionNumber)")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            Button(isEditing ? "Done" : "Edit") {
                isEditing.toggle()
            }
            .foregroundColor(.cyan)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
    }

    // MARK: - Status header

    private var statusHeader: some View {
        HStack(spacing: 20) {
            statusPill(
                icon: "wave.3.forward",
                label: "RGB+Depth",
                done: session.hasScan,
                color: .cyan
            )

            statusPill(
                icon: "doc.text.fill",
                label: "Metadata",
                done: session.captureMetadataFilename != nil,
                color: .green
            )

            statusPill(
                icon: "cube.transparent.fill",
                label: "PLY",
                done: session.plyFilename != nil,
                color: .purple
            )

            statusPill(
                icon: "scalemass.fill",
                label: session.hasWeight ? "\(Int(session.knownWeightKg ?? 0))kg" : "Weight",
                done: session.hasWeight,
                color: .orange
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func statusPill(icon: String, label: String, done: Bool, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: done ? icon : "\(icon).slash")
                .font(.title2)
                .foregroundColor(done ? color : .gray.opacity(0.4))

            Text(label)
                .font(.caption.bold())
                .foregroundColor(done ? .white : .gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Capture preview

    private var capturePreviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture")
                .font(.subheadline.bold())
                .foregroundColor(.white)

            Group {
                if let url = session.rgbCaptureURL(),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: displayImage(image))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))

                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundColor(.gray)

                            Text("No RGB preview available")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .frame(height: 190)
            .clipped()
            .cornerRadius(10)

            HStack {
                fileTag("RGB", session.rgbCaptureFilename != nil)
                fileTag("Depth", session.depthCaptureFilename != nil)
                fileTag("Meta", session.captureMetadataFilename != nil)
                fileTag("PLY", session.plyFilename != nil)
                Spacer()
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func fileTag(_ label: String, _ present: Bool) -> some View {
        Text(label)
            .font(.caption.bold())
            .foregroundColor(present ? .black : .gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(present ? Color.cyan : Color.white.opacity(0.08))
            .cornerRadius(8)
    }

    // MARK: - Details

    private var viewDetailsCard: some View {
        VStack(spacing: 0) {
            detailRow("Breed", session.breed.rawValue)
            Divider().background(Color.white.opacity(0.08))
            detailRow("Sex", session.sex.rawValue)
            Divider().background(Color.white.opacity(0.08))
            detailRow("Location", session.location.rawValue)
            Divider().background(Color.white.opacity(0.08))
            detailRow("Weight", session.hasWeight ? "\(Int(session.knownWeightKg ?? 0)) kg" : "Not recorded")

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

    // MARK: - Weight estimate / JSON response

    private var weightEstimateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Weight Estimate", systemImage: "scalemass.fill")
                .font(.subheadline.bold())
                .foregroundColor(.orange)

            weightEstimateBody
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2)))
    }

    @ViewBuilder
    private var weightEstimateBody: some View {
        switch session.weightEstimateState {
        case .notRequested:
            Text("No estimate requested yet")
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
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(kg.rounded()))")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                        Text("kg")
                            .font(.title3.bold())
                            .foregroundColor(.orange.opacity(0.7))
                    }
                    Label("Predicted weight", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .frame(maxWidth: .infinity)
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

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 10) {
            // Only show when a scan exists; disabled while a request is in-flight
            if session.hasScan {
                Button(action: recalculateWeight) {
                    Label(
                        session.weightEstimateState == .waiting
                            ? "Requesting…"
                            : "Recalculate Weight",
                        systemImage: "arrow.clockwise.circle.fill"
                    )
                    .font(.subheadline.bold())
                    .foregroundColor(session.weightEstimateState == .waiting ? .gray : .orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(session.weightEstimateState == .waiting ? 0.1 : 0.3))
                    )
                }
                .buttonStyle(.plain)
                .disabled(session.weightEstimateState == .waiting)
            }

            Button(action: shareThisAnimal) {
                Label("Share This Animal", systemImage: "square.and.arrow.up")
                    .font(.subheadline.bold())
                    .foregroundColor(.cyan)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.cyan.opacity(0.3))
                    )
            }
            .buttonStyle(.plain)

            Button(action: { showDeleteConfirm = true }) {
                Label("Delete Animal \(session.sessionNumber)", systemImage: "trash")
                    .font(.subheadline.bold())
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.2))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func displayImage(_ image: UIImage) -> UIImage {
        if image.size.width > image.size.height {
            return image
        }
        return image
    }

    // MARK: - Actions implementation

    private func recalculateWeight() {
        session.refreshCaptureFilenamesFromDiskIfNeeded()
        NetworkService.shared.submitScanForWeightEstimate(session)
    }

    private func shareThisAnimal() {
        session.refreshCaptureFilenamesFromDiskIfNeeded()
        session.save()

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
            items = ["Animal \(session.sessionNumber): \(session.displayName)"]
        }

        sharePayload = SharePayload(items: items)
    }

    private func deleteSession() {
        let folder = AnimalSession.sessionFolder(for: session)

        if let rgb = session.rgbCaptureFilename {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(rgb))
        }

        if let depth = session.depthCaptureFilename {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(depth))
        }

        if let meta = session.captureMetadataFilename {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(meta))
        }

        if let ply = session.plyFilename {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(ply))
        }

        let jsonURL = AnimalSession.sessionsDirectory().appendingPathComponent("\(session.id).json")
        try? FileManager.default.removeItem(at: jsonURL)
        try? FileManager.default.removeItem(at: folder)

        onUpdate()
        dismiss()
    }
}

// MARK: - Inline edit card

struct EditDetailsCard: View {
    @ObservedObject var session: AnimalSession
    @State private var weightText: String = ""
    @State private var selectedBreed: Breed = .angus
    @State private var selectedSex: AnimalSex = .steer
    @State private var selectedLocation: ScanLocation = .saleyard
    @State private var notes: String = ""

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Weight (kg)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Spacer()

                TextField("0", text: $weightText)
                    .font(.title3.bold())
                    .foregroundColor(.orange)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                Text("Breed")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Breed.allCases, id: \.self) { breed in
                        Button(action: {
                            selectedBreed = breed
                            save()
                        }) {
                            Text(breed.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(selectedBreed == breed ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedBreed == breed ? Color.cyan : Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sex")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(AnimalSex.allCases, id: \.self) { sex in
                        Button(action: {
                            selectedSex = sex
                            save()
                        }) {
                            Text(sex.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(selectedSex == sex ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedSex == sex ? Color.cyan : Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ScanLocation.allCases, id: \.self) { location in
                        Button(action: {
                            selectedLocation = location
                            save()
                        }) {
                            Text(location.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(selectedLocation == location ? .black : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedLocation == location ? Color.cyan : Color.white.opacity(0.08))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                TextField("Notes...", text: $notes, axis: .vertical)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(3...5)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(8)
                    .onChange(of: notes) { _ in save() }
            }
            .padding(14)
            .background(Color.white.opacity(0.05))
            .cornerRadius(10)
        }
        .onAppear {
            weightText = session.knownWeightKg.map { String(format: "%.0f", $0) } ?? ""
            selectedBreed = session.breed
            selectedSex = session.sex
            selectedLocation = session.location
            notes = session.notes
        }
        .onChange(of: weightText) { _ in save() }
    }

    private func save() {
        if let w = Double(weightText.replacingOccurrences(of: ",", with: ".")) {
            session.knownWeightKg = w
        } else if weightText.isEmpty {
            session.knownWeightKg = nil
        }

        session.breed = selectedBreed
        session.sex = selectedSex
        session.location = selectedLocation
        session.notes = notes
        session.save()
    }
}
