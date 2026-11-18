import SwiftUI
import AVFoundation
import UIKit
import MobileVLCKit

final class VLCPlayerController: ObservableObject {
    let mediaPlayer = VLCMediaPlayer()
    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = ""

    func play(urlString: String, title: String) {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned) else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        mediaPlayer.stop()
        let media = VLCMedia(url: url)
        media.addOptions([
            "network-caching": 1500,
            "live-caching": 1500,
            "clock-jitter": 0,
            "clock-synchro": 0,
            "http-user-agent": "VLC/3.0.20 LibVLC/3.0.20",
            "http-reconnect": true
        ])
        mediaPlayer.media = media
        mediaPlayer.play()
        currentTitle = title
        isPlaying = true
    }

    func togglePlayPause() {
        if mediaPlayer.isPlaying {
            mediaPlayer.pause()
            isPlaying = false
        } else {
            mediaPlayer.play()
            isPlaying = true
        }
    }

    func jump(seconds: Int32) {
        if seconds < 0 {
            mediaPlayer.jumpBackward(abs(seconds))
        } else {
            mediaPlayer.jumpForward(seconds)
        }
    }

    func stop() {
        mediaPlayer.stop()
        isPlaying = false
    }
}

struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable as? UIView !== uiView {
            player.drawable = uiView
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: CatalogStore
    @EnvironmentObject var downloader: DownloadService
    @StateObject private var vlc = VLCPlayerController()

    @State private var selectedTab: AppTab = .home
    @State private var currentItem: MediaItem?
    @State private var isFullScreen: Bool = false
    @State private var showDownloads: Bool = false
    @State private var expandedGroup: String?
    @State private var downloadBannerText: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Sfondo ambientale profondo stile Liquid Glass
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.10),
                    Color(red: 0.08, green: 0.09, blue: 0.13),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.orange.opacity(0.10))
                .frame(width: 300, height: 300)
                .blur(radius: 85)
                .offset(x: -110, y: -250)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 130, y: 240)

            if selectedTab == .settings {
                SettingsTabView()
                    .environmentObject(store)
                    .environmentObject(downloader)
                    .padding(.bottom, 86)
            } else {
                VStack(spacing: 10) {
                    // Header superiore compatto
                    HStack(spacing: 10) {
                        Text("TessyTV")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)

                        if store.isSyncing {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Sync...")
                                    .font(.caption2.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .liquidGlassSurface(cornerRadius: 12)
                        }

                        Spacer()

                        Button {
                            showDownloads = true
                        } label: {
                            Label(
                                downloader.activeCount > 0 ? "Download (\(downloader.activeCount))" : "Download",
                                systemImage: "arrow.down.circle.fill"
                            )
                        }
                        .buttonStyle(LiquidGlassChipStyle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 6)

                    if let banner = downloadBannerText {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.25))
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

                    // Schermo Riproduzione arrotondato con motore MobileVLCKit (supporto Live .ts e .m3u8)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.10), Color.white.opacity(0.24)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 6)

                        if currentItem != nil {
                            VLCVideoSurface(player: vlc.mediaPlayer)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "play.tv")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.35))
                                Text("Seleziona un canale, film o serie")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                    }
                    .frame(height: 210)
                    .padding(.horizontal, 12)

                    // Pillola Controlli Player Liquid Glass
                    HStack(spacing: 10) {
                        Button {
                            vlc.togglePlayPause()
                        } label: {
                            Image(systemName: vlc.isPlaying ? "pause.fill" : "play.fill")
                                .frame(width: 34, height: 30)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 0.96, green: 0.65, blue: 0.25), Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }

                        Button("-15s") { vlc.jump(seconds: -15) }
                            .buttonStyle(LiquidGlassPillButtonStyle())

                        Button("+15s") { vlc.jump(seconds: 15) }
                            .buttonStyle(LiquidGlassPillButtonStyle())

                        Button {
                            vlc.stop()
                            currentItem = nil
                        } label: {
                            Image(systemName: "stop.fill")
                        }
                        .buttonStyle(LiquidGlassPillButtonStyle())

                        Spacer()

                        if let item = currentItem, item.kind != .live {
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

                    // Barra di ricerca adattiva alla sezione attiva
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.5))
                                .font(.caption)
                            TextField("Cerca in \(selectedTab.title)...", text: $store.searchQuery)
                                .textFieldStyle(.plain)
                                .foregroundColor(.white)
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
                    .padding(.horizontal, 12)

                    // Contenuto Catalogo (Home evidenza o Liste per Channels / Movies / Series)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            if !store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                                ForEach(store.items) { item in
                                    channelRow(item)
                                }
                            } else if selectedTab == .home {
                                if !store.recentItems.isEmpty {
                                    Text("Canali Live in evidenza")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.25))
                                        .padding(.bottom, 2)

                                    ForEach(store.recentItems) { item in
                                        channelRow(item)
                                    }
                                } else {
                                    VStack(spacing: 8) {
                                        Text("Nessuna lista caricata")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.85))
                                        Text("Vai nella scheda Settings in basso a destra per inserire il tuo link M3U.")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.55))
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 28)
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
                                    .tint(Color(red: 0.96, green: 0.65, blue: 0.25))
                                    .contextMenu {
                                        Button("Sposta categoria in Channels") { store.moveGroup(grp, to: .live) }
                                        Button("Sposta categoria in Movies") { store.moveGroup(grp, to: .vod) }
                                        Button("Sposta categoria in Series") { store.moveGroup(grp, to: .series) }
                                        Divider()
                                        Button("Rimuovi intera categoria", role: .destructive) { store.deleteGroup(grp) }
                                    }
                                }
                            }
                        }
                        .padding(10)
                    }
                    .liquidGlassSurface(cornerRadius: 14)
                    .padding(.horizontal, 12)

                    // Status bar sopra la tab bar flottante
                    HStack {
                        Text(store.statusText)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.55))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 84)
                }
            }

            // Menu Flottante Liquid Glass (Home, Channels, Movies, Series, Settings)
            LiquidGlassFloatingTabBar(selectedTab: $selectedTab)
                .onChange(of: selectedTab) { newTab in
                    expandedGroup = nil
                    if newTab != .settings {
                        store.selectedCategory = newTab.mediaKind
                        store.onCategoryChanged()
                    }
                }
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsSheetView()
                .environmentObject(downloader)
        }
        .fullScreenCover(isPresented: $isFullScreen) {
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                VLCVideoSurface(player: vlc.mediaPlayer).ignoresSafeArea()
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
                currentItem = item
                vlc.play(urlString: item.url, title: item.title)
                store.statusText = "Riproduzione: \(item.title)"
            } label: {
                HStack {
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundColor(currentItem?.id == item.id ? Color(red: 0.96, green: 0.65, blue: 0.25) : .white.opacity(0.9))
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
        .contextMenu {
            Button("Sposta in Channels (Live)") { store.moveItem(item, to: .live) }
            Button("Sposta in Movies (Film)") { store.moveItem(item, to: .vod) }
            Button("Sposta in Series (Serie)") { store.moveItem(item, to: .series) }
            Divider()
            Button("Rimuovi canale", role: .destructive) { store.deleteItem(item) }
        }
    }
}

struct LiquidGlassFloatingTabBar: View {
    @Binding var selectedTab: AppTab
    @Namespace private var tabSelectionNS

    private let activeAmber = Color(red: 0.96, green: 0.65, blue: 0.25)

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = (selectedTab == tab)
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(isSelected ? activeAmber : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Color.black.opacity(0.45))
                                .matchedGeometryEffect(id: "LIQUID_GLASS_ACTIVE_TAB", in: tabSelectionNS)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.40),
                                    Color.white.opacity(0.08),
                                    Color.white.opacity(0.24)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.48), radius: 18, x: 0, y: 10)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var store: CatalogStore
    @EnvironmentObject var downloader: DownloadService
    @State private var urlInput: String = UserDefaults.standard.string(forKey: "tessytv_saved_m3u_url") ?? ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Settings")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sorgente Lista Canali M3U")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.25))

                    TextField("Inserisci URL file M3U...", text: $urlInput)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)

                    Button {
                        Task {
                            await store.importFromURL(urlString: urlInput)
                        }
                    } label: {
                        HStack {
                            if store.isSyncing {
                                ProgressView().tint(.black)
                            }
                            Text("Salva e Aggiorna Lista")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(red: 0.96, green: 0.65, blue: 0.25))
                        .foregroundColor(.black)
                        .cornerRadius(11)
                    }
                }
                .padding(14)
                .liquidGlassSurface(cornerRadius: 15)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Gestione Database Locale")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)

                    Text("Stato: \(store.statusText)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))

                    Button("Rimuovi / Svuota lista M3U attuale") {
                        store.clearCatalog()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .font(.subheadline.weight(.bold))
                    .cornerRadius(11)
                }
                .padding(14)
                .liquidGlassSurface(cornerRadius: 15)
            }
            .padding(.horizontal, 14)
        }
    }
}

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
                                    .tint(Color(red: 0.96, green: 0.65, blue: 0.25))
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
