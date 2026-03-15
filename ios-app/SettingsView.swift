import SwiftUI
internal import Combine

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var defaultBreed: Breed {
        didSet { UserDefaults.standard.set(defaultBreed.rawValue, forKey: "defaultBreed") }
    }

    @Published var defaultSex: AnimalSex {
        didSet { UserDefaults.standard.set(defaultSex.rawValue, forKey: "defaultSex") }
    }

    @Published var defaultLocation: ScanLocation {
        didSet { UserDefaults.standard.set(defaultLocation.rawValue, forKey: "defaultLocation") }
    }

    init() {
        let b = UserDefaults.standard.string(forKey: "defaultBreed") ?? ""
        let s = UserDefaults.standard.string(forKey: "defaultSex") ?? ""
        let l = UserDefaults.standard.string(forKey: "defaultLocation") ?? ""

        defaultBreed = Breed(rawValue: b) ?? .angus
        defaultSex = AnimalSex(rawValue: s) ?? .steer
        defaultLocation = ScanLocation(rawValue: l) ?? .saleyard
    }
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var showDeleteAll = false
    @State private var showShareAll = false
    @State private var shareAllItems: [Any] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(.cyan)
                    }

                    Spacer()

                    Text("Settings")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Color.clear.frame(width: 60)
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 20) {
                        sectionCard(
                            title: "Default Breed",
                            subtitle: "Pre-selected when you start a new animal"
                        ) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(Breed.allCases, id: \.self) { breed in
                                    Button(action: { settings.defaultBreed = breed }) {
                                        Text(breed.rawValue)
                                            .font(.subheadline.bold())
                                            .foregroundColor(settings.defaultBreed == breed ? .black : .gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(settings.defaultBreed == breed ? Color.cyan : Color.white.opacity(0.08))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        sectionCard(title: "Default Sex", subtitle: "") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(AnimalSex.allCases, id: \.self) { sex in
                                    Button(action: { settings.defaultSex = sex }) {
                                        Text(sex.rawValue)
                                            .font(.subheadline.bold())
                                            .foregroundColor(settings.defaultSex == sex ? .black : .gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(settings.defaultSex == sex ? Color.cyan : Color.white.opacity(0.08))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        sectionCard(title: "Default Location", subtitle: "") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(ScanLocation.allCases, id: \.self) { loc in
                                    Button(action: { settings.defaultLocation = loc }) {
                                        Text(locationLabel(loc))
                                            .font(.subheadline.bold())
                                            .foregroundColor(settings.defaultLocation == loc ? .black : .gray)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(settings.defaultLocation == loc ? Color.cyan : Color.white.opacity(0.08))
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        sectionCard(title: "Data", subtitle: "Manage all your recorded sessions") {
                            VStack(spacing: 10) {
                                Button(action: exportAll) {
                                    Label("Export All Sessions", systemImage: "square.and.arrow.up.on.square")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.cyan)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.cyan.opacity(0.1))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.cyan.opacity(0.3))
                                        )
                                }
                                .buttonStyle(.plain)

                                Button(action: { showDeleteAll = true }) {
                                    Label("Delete All Sessions", systemImage: "trash.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.red.opacity(0.08))
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.red.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(spacing: 4) {
                            Text("CattleScan v2.0")
                                .font(.caption)
                                .foregroundColor(.gray)

                            Text("Silver Lion Consulting")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showShareAll) {
            ShareSheet(items: shareAllItems)
        }
        .alert("Delete All Sessions?", isPresented: $showDeleteAll) {
            Button("Delete All", role: .destructive) { deleteAllSessions() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all captures and data. This cannot be undone.")
        }
    }

    private func locationLabel(_ loc: ScanLocation) -> String {
        switch loc {
        case .crush: return "Crush"
        case .field: return "Field"
        case .saleyard: return "Saleyard"
        case .feedlot: return "Feedlot"
        }
    }

    private func sectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            content()
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
    }

    private func exportAll() {
        let sessions = AnimalSession.loadAll()
        var items: [Any] = []

        for session in sessions {
            let folder = AnimalSession.sessionFolder(for: session)

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
        }

        if items.isEmpty {
            items.append("No sessions to export")
        }

        shareAllItems = items
        showShareAll = true
    }

    private func deleteAllSessions() {
        let sessions = AnimalSession.loadAll()
        let sessionsDir = AnimalSession.sessionsDirectory()

        for session in sessions {
            if let rgb = session.rgbCaptureFilename {
                try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session).appendingPathComponent(rgb))
            }

            if let depth = session.depthCaptureFilename {
                try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session).appendingPathComponent(depth))
            }

            if let meta = session.captureMetadataFilename {
                try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session).appendingPathComponent(meta))
            }

            if let legacyPLY = session.plyFilename {
                try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session).appendingPathComponent(legacyPLY))
            }
            
            if let ply = session.plyFilename {
                try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session).appendingPathComponent(ply))
            }

            try? FileManager.default.removeItem(at: sessionsDir.appendingPathComponent("\(session.id).json"))
            try? FileManager.default.removeItem(at: AnimalSession.sessionFolder(for: session))
        }
    }
}
