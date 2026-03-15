import SwiftUI

@main
struct CowdarApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {  // ← required here
                CameraView()
            }
        }
    }
}
