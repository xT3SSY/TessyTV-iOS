import Foundation

enum MediaKind: String, CaseIterable, Identifiable {
    case all = "All"
    case live = "Channels"
    case vod = "Movies"
    case series = "Series"

    var id: String { rawValue }
}

enum AppTab: Int, CaseIterable, Identifiable {
    case home, channels, movies, series, settings
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .channels: return "Channels"
        case .movies: return "Movies"
        case .series: return "Series"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .channels: return "dot.radiowaves.left.and.right"
        case .movies: return "film"
        case .series: return "tv"
        case .settings: return "gearshape"
        }
    }

    var mediaKind: MediaKind {
        switch self {
        case .home: return .all
        case .channels: return .live
        case .movies: return .vod
        case .series: return .series
        case .settings: return .all
        }
    }
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
