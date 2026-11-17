import SwiftUI
import AVKit
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var store: CatalogStore
    @EnvironmentObject var downloader: DownloadService

    @State private var currentItem: MediaItem?
    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var isFullScreen: Bool = false
    @State private var showSettings: Bool = false
    @State private var showDownloads: Bool = false
    @State private var expandedGroup: String?
    @State private var downloadBannerText: String?

    var body: some View {
        ZStack {
            // Sfondo ambientale profondo stile Liquid Glass
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.13),
                    Color(red: 0.09, green: 0.10, blue: 0.14),
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.blue.opacity(0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -110, y: -260)

            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 280, height: 280)
                .blur(radius: 75)
                .offset(x: 130, y: 240)

            VStack(spacing: 10) {
                // Barra superiore Liquid Glass
                HStack(spacing: 10) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape.fill")
                    }
                    .buttonStyle(LiquidGlassChipStyle())

                    Button {
                        showDownloads = true
                    } label: {
                        Label(
                            downloader.activeCount > 0 ? "Download (\(downloader.activeCount))" : "Download",
                            systemImage: "arrow.down.circle.fill"
                        )
                    }
                    .buttonStyle(LiquidGlassChipStyle())

                    Spacer()

                    if store.isSyncing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text("Sync...")
                                .font(.caption2.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .liquidGlassSurface(cornerRadius: 14)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                if let banner = downloadBannerText {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.cyan)
                        Text(banner)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .liquidGlassSurface(cornerRadius: 12)
                    .padding(.horizontal, 12)
                }

                // Schermo Riproduzione arrotondato con bordo speculare Liquid Glass
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.45), Color.white.opacity(0.12), Color.white.opacity(0.28)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)

                    if let player = player {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "play.tv")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.35))
                            Text(currentItem?.title ?? "Seleziona un canale o un film")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .frame(height: 215)
                .padding(.horizontal, 12)

                // Pillola Controlli Player Liquid Glass
                HStack(spacing: 10) {
                    Button {
                        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                        try? AVAudioSession.sharedInstance().setActive(true)
                        if isPlaying { player?.pause() } else { player?.play() }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 34, height: 30)
                            .background(
                                LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    Button("-15s") { seekBy(-15) }
                        .buttonStyle(LiquidGlassPillButtonStyle())

                    Button("+15s") { seekBy(15) }
                        .buttonStyle(LiquidGlassPillButtonStyle())

                    Button {
                        player?.pause()
                        player = nil
                        isPlaying = false
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(LiquidGlassPillButtonStyle())

                    Spacer()

                    if let item = currentItem {
                        Button {
                            downloader.enqueue(title: item.title, urlString: item.url)
                            downloadBannerText = "Aggiunto ai download: \(item.title)"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                downloadBannerText = nil
                            }
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                        }
                        .buttonStyle(LiquidGlassPillButtonStyle())
                    }

                    Button {
                        isFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(LiquidGlassPillButtonStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlassSurface(cornerRadius: 15)
                .padding(.horizontal, 12)

                // Selettore Sezioni (All, Live, Film, Serie) + Ricerca
                VStack(spacing: 8) {
                    Picker("Categoria", selection: $store.selectedCategory) {
                        ForEach(MediaKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.selectedCategory) { _ in
                        expandedGroup = nil
                        store.onCategoryChanged()
                    }

                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.caption)
                            TextField("Cerca canale, film o serie...", text: $store.searchQuery)
                                .textFieldStyle(.plain)
                                .onSubmit { store.performSearch() }
                            if !store.searchQuery.isEmpty {
                                Button {
                                    store.searchQuery = ""
                                    store.performSearch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.45))
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .liquidGlassSurface(cornerRadius: 11)

                        Button("Invio") { store.performSearch() }
                            .buttonStyle(LiquidGlassPillButtonStyle())
                    }

                    if store.isSearching {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.75)
                            Text("Sto cercando '\(store.searchQuery)'...")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.cyan)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .liquidGlassSurface(cornerRadius: 10)
                    }
                }
                .padding(.horizontal, 12)

                // Riquadro Lista Canali / Film / Serie con stile Liquid Glass
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(store.items) { item in
                                channelRow(item)
                            }
                        } else {
                            ForEach(store.groups, id: \.self) { grp in
                                DisclosureGroup(
                                    isExpanded: Binding(
                                        get: { expandedGroup == grp },
                                        set: { expandedGroup = $0 ? grp : nil }
                                    )
                                ) {
                                    ForEach(store.itemsForGroup(grp)) { item in
                                        channelRow(item)
                                            .padding(.leading, 12)
                                    }
                                } label: {
                                    Text(grp)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white.opacity(0.92))
                                        .padding(.vertical, 4)
                                }
                                .tint(.cyan)
                            }
                        }
                    }
                    .padding(10)
                }
                .liquidGlassSurface(cornerRadius: 14)
                .padding(.horizontal, 12)

                // Status bar
                HStack {
                    Text(store.statusText)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsSheetView()
                .environmentObject(downloader)
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let player = player {
                    VideoPlayer(player: player).ignoresSafeArea()
                }
                Button {
                    isFullScreen = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.85))
                        .padding()
                }
            }
        }
    }

    private func channelRow(_ item: MediaItem) -> some View {
        HStack(spacing: 8) {
            Button {
                play(item)
            } label: {
                HStack {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundColor(currentItem?.id == item.id ? .cyan : .white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }

            if item.kind != .live {
                Button {
                    downloader.enqueue(title: item.title, urlString: item.url)
                    downloadBannerText = "Download avviato: \(item.title)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        downloadBannerText = nil
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.trailing, 6)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(currentItem?.id == item.id ? Color.white.opacity(0.14) : Color.clear)
        )
    }

    private func play(_ item: MediaItem) {
        guard let url = URL(string: item.url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        currentItem = item
        let headers = ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.volume = 1.0
        avPlayer.isMuted = false

        self.player = avPlayer
        avPlayer.play()
        self.isPlaying = true
        store.statusText = "Riproduzione: \(item.title)"
    }

    private func seekBy(_ seconds: Double) {
        guard let player = player else { return }
        let current = CMTimeGetSeconds(player.currentTime())
        let target = CMTime(seconds: max(0, current + seconds), preferredTimescale: 600)
        player.seek(to: target)
    }
}

// Modificatore stile Apple Liquid Glass
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.42),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func liquidGlassSurface(cornerRadius: CGFloat = 12) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

struct LiquidGlassChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlassSurface(cornerRadius: 12)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
    }
}

struct LiquidGlassPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundColor(.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

struct SettingsSheetView: View {
    @EnvironmentObject var store: CatalogStore
    @Environment(\.dismiss) var dismiss
    @State private var urlInput: String = UserDefaults.standard.string(forKey: "tessytv_saved_m3u_url") ?? ""

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                GroupBox("Sorgenti Lista Canali / Catalogo") {
                    VStack(spacing: 10) {
                        TextField("Inserisci URL file M3U...", text: $urlInput)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)

                        Button("Salva e Aggiorna URL M3U") {
                            Task {
                                await store.importFromURL(urlString: urlInput)
                                dismiss()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.top, 6)
                }

                Text("Gestione lista M3U / Catalogo salvato nel database locale dell'iPhone:")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("Rimuovi / Svuota lista M3U attuale") {
                    store.clearCatalog()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.75))
                .foregroundColor(.white)
                .font(.subheadline.weight(.bold))
                .cornerRadius(10)

                Button("Chiudi") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Spacer()
            }
            .padding()
            .navigationTitle("Impostazioni TessyTV")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct DownloadsSheetView: View {
    @EnvironmentObject var downloader: DownloadService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Button("Annulla tutti") {
                        downloader.cancelAll()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.75))
                    .foregroundColor(.white)
                    .font(.caption.weight(.bold))
                    .cornerRadius(8)

                    Button("Pulisci completati") {
                        downloader.clearCompleted()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.14))
                    .foregroundColor(.white)
                    .font(.caption)
                    .cornerRadius(8)

                    Spacer()
                }

                GroupBox("Coda Download (1 alla volta)") {
                    if downloader.tasks.isEmpty {
                        Text("Nessun download avviato.")
                            .font(.caption.italic())
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, minHeight: 160)
                    } else {
                        List(downloader.tasks) { task in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.title)
                                    .font(.subheadline.weight(.medium))
                                ProgressView(value: task.progress)
                                    .tint(.cyan)
                                Text(task.status)
                                    .font(.caption)
                                    .foregroundColor(task.isFailed ? .red : .gray)
                            }
                            .padding(.vertical, 4)
                        }
                        .listStyle(.plain)
                    }
                }

                Button("Chiudi") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Spacer()
            }
            .padding()
            .navigationTitle("Gestione Download")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
