import Foundation

enum MediaKind: String, CaseIterable, Identifiable {
    case all = "All"
    case live = "Live"
    case vod = "Film"
    case series = "Serie"

    var id: String { rawValue }
}

struct MediaItem: Identifiable, Hashable {
    let id: Int64
    let group: String
    let title: String
    let url: String
    let kind: MediaKind
}

struct DownloadTaskItem: Identifiable {
    let id = UUID()
    let title: String
    let url: String
    var progress: Double = 0.0
    var status: String = "In coda"
    var isCompleted: Bool = false
    var isFailed: Bool = false
    var localURL: URL?
}
