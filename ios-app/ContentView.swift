import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var sessions: [AnimalSession] = []
    @State private var activeSession: AnimalSession? = nil
    @State private var viewingSession: AnimalSession? = nil
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    logoHeader

                    if sessions.isEmpty {
                        emptyState
                    } else {
                        sessionList
                    }

                    newAnimalButton
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                reloadSessions()
            }
            .fullScreenCover(item: $activeSession) { session in
                SessionCaptureView(session: session) {
                    reloadSessions()
                }
            }
            .fullScreenCover(item: $viewingSession) { session in
                AnimalDetailView(session: session) {
                    reloadSessions()
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }

    private var logoHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .padding(.trailing, 20)
            }

            Image("AppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .cornerRadius(20)
                .shadow(color: .cyan.opacity(0.4), radius: 12)

            Text("CattleScan")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("LiDAR Weight Estimation")
                .font(.caption)
                .foregroundColor(.cyan)
                .tracking(1.5)
                .textCase(.uppercase)

            if !sessions.isEmpty {
                Text("\(sessions.count) animal\(sessions.count == 1 ? "" : "s") recorded")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 30)
        .padding(.bottom, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "pawprint.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))

            Text("No animals recorded yet")
                .font(.headline)
                .foregroundColor(.gray)

            Text("Tap New Animal to start capturing")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.6))

            Spacer()
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(sessions) { session in
                    SessionRowView(session: session) {
                        viewingSession = session
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var newAnimalButton: some View {
        Button(action: startNewSession) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)

                Text("New Animal")
                    .font(.title3.bold())
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [.cyan, Color(red: 0, green: 0.9, blue: 0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 40)
        .padding(.top, 12)
    }

    private func startNewSession() {
        let session = AnimalSession(sessionNumber: AnimalSession.nextSessionNumber())
        session.breed = settings.defaultBreed
        session.sex = settings.defaultSex
        session.location = settings.defaultLocation
        session.save()
        // Register before any other code can create a competing instance for
        // this id (e.g. an immediate reloadSessions after the scan completes).
        SessionStore.shared.register(session)
        activeSession = session
    }

    private func reloadSessions() {
        // Use the store so existing in-memory instances are reused — this
        // keeps NetworkService's @Published mutations visible to any
        // AnimalDetailView that is already open and observing a session.
        sessions = SessionStore.shared.reload()
    }
}

struct SessionRowView: View {
    let session: AnimalSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                thumbnail

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)

                    Text(session.completionStatus)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(session.hasScan ? Color.cyan : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)

                    Circle()
                        .fill(session.hasWeight ? Color.orange : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(14)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var thumbnail: some View {
        Group {
            if let url = session.rgbCaptureURL(),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.cyan.opacity(0.15))

                    Image(systemName: "photo")
                        .foregroundColor(.cyan)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .cornerRadius(10)
    }
}
