import SwiftUI
import AVKit

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

    var body: some View {
        ZStack {
            Color(red: 0.12, green: 0.125, blue: 0.135).ignoresSafeArea()

            VStack(spacing: 10) {
                // Barra superiore (Impostazioni / Download)
                HStack(spacing: 16) {
                    Button("Impostazioni") { showSettings = true }
                    Button(downloader.activeCount > 0 ? "Download (\(downloader.activeCount))" : "Download") {
                        showDownloads = true
                    }
                    Spacer()
                    if store.isSyncing {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("Aggiorno lista canali...")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(8)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.top, 6)

                // Area Schermo Nero Arrotondato con contorno bianco sottile
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )

                    if let player = player {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text(currentItem?.title ?? "Seleziona un canale o un film")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 12)

                // Pillola Controlli Player arrotondata con contorno bianco sottile
                HStack(spacing: 12) {
                    Button {
                        if isPlaying { player?.pause() } else { player?.play() }
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 32, height: 28)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }

                    Button("-15s") { seekBy(-15) }
                        .buttonStyle(TessyControlPillStyle())

                    Button("+15s") { seekBy(15) }
                        .buttonStyle(TessyControlPillStyle())

                    Button {
                        player?.pause()
                        player = nil
                        isPlaying = false
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(TessyControlPillStyle())

                    Spacer()

                    if let item = currentItem {
                        Button {
                            downloader.enqueue(title: item.title, urlString: item.url)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(TessyControlPillStyle())
                    }

                    Button {
                        isFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(TessyControlPillStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 12)

                // Filtro Categoria + Barra di Ricerca + Pulsante Invio
                VStack(spacing: 8) {
                    Picker("Categoria", selection: $store.selectedCategory) {
                        ForEach(MediaKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: store.selectedCategory) { _ in
                        store.performSearch()
                    }

                    HStack(spacing: 8) {
                        TextField("Cerca canale, film o serie...", text: $store.searchQuery)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.15, green: 0.16, blue: 0.17))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                            .onSubmit { store.performSearch() }

                        Button("Invio") { store.performSearch() }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.17, green: 0.17, blue: 0.19))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.4), lineWidth: 1))
                    }

                    if store.isSearching {
                        HStack {
                            Text("🔍 Sto cercando '\(store.searchQuery)'...")
                                .font(.caption.weight(.medium))
                                .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.11, green: 0.15, blue: 0.20))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 12)

                // Riquadro Lista Canali con tutti e 4 gli angoli arrotondati
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
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .background(Color(red: 0.118, green: 0.122, blue: 0.133))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(red: 0.235, green: 0.247, blue: 0.263), lineWidth: 1)
                )
                .padding(.horizontal, 12)

                // Status bar in basso
                HStack {
                    Text(store.statusText)
                        .font(.caption2.italic())
                        .foregroundColor(.gray)
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
        Button {
            play(item)
        } label: {
            HStack {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(currentItem?.id == item.id ? .blue : .white)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(currentItem?.id == item.id ? Color.white.opacity(0.08) : Color.clear)
            .cornerRadius(5)
        }
    }

    private func play(_ item: MediaItem) {
        guard let url = URL(string: item.url) else { return }
        currentItem = item
        let avPlayer = AVPlayer(url: url)
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

struct TessyControlPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.17, green: 0.18, blue: 0.20))
            .foregroundColor(.white)
            .cornerRadius(6)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// Finestra Impostazioni TessyTV (stile identico alla versione Desktop)
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
                        .padding(.vertical, 8)
                        .background(Color(red: 0.22, green: 0.23, blue: 0.25))
                        .foregroundColor(.white)
                        .cornerRadius(6)
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
                .background(Color(red: 0.65, green: 0.15, blue: 0.15))
                .foregroundColor(.white)
                .font(.subheadline.weight(.bold))
                .cornerRadius(6)

                Button("Chiudi") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.22, green: 0.23, blue: 0.25))
                    .foregroundColor(.white)
                    .cornerRadius(6)

                Spacer()
            }
            .padding()
            .navigationTitle("Impostazioni TessyTV")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// Finestra Gestione Download (esteticamente identica a Impostazioni TessyTV)
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
                    .background(Color(red: 0.65, green: 0.15, blue: 0.15))
                    .foregroundColor(.white)
                    .font(.caption.weight(.bold))
                    .cornerRadius(6)

                    Button("Pulisci completati") {
                        downloader.clearCompleted()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.22, green: 0.23, blue: 0.25))
                    .foregroundColor(.white)
                    .font(.caption)
                    .cornerRadius(6)

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
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(task.title).font(.subheadline)
                                    Text(task.status).font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                            }
                        }
                        .listStyle(.plain)
                    }
                }

                Button("Chiudi") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.22, green: 0.23, blue: 0.25))
                    .foregroundColor(.white)
                    .cornerRadius(6)

                Spacer()
            }
            .padding()
            .navigationTitle("Gestione Download")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
