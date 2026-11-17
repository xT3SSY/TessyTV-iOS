import SwiftUI
import AVFoundation

@main
struct TessyTVApp: App {
    @StateObject private var store = CatalogStore()
    @StateObject private var downloader = DownloadService()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(downloader)
                .preferredColorScheme(.dark)
                .onAppear {
                    configureAudioSession()
                }
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSession error: \(error.localizedDescription)")
        }
    }
}
