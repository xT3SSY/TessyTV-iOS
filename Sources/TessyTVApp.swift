import SwiftUI

@main
struct TessyTVApp: App {
    @StateObject private var store = CatalogStore()
    @StateObject private var downloader = DownloadService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(downloader)
                .preferredColorScheme(.dark)
        }
    }
}
