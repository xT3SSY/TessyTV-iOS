import SwiftUI
import AVKit
import AVFoundation
import UIKit
import MobileVLCKit

// Controller unificato: usa AVPlayerViewController nativo iOS (Liquid Glass ufficiale) quando compatibile
// e MobileVLCKit per i flussi Live MPEG-TS (.ts) grezzi con HUD Liquid Glass completo
final class HybridPlayerController: ObservableObject {
    let vlcPlayer = VLCMediaPlayer()
    @Published var avPlayer: AVPlayer?
    @Published var useNativeAVPlayer: Bool = false
    @Published var isPlaying: Bool = false
    @Published var currentTitle: String = ""
    @Published var isLiveStream: Bool = false

    @Published var currentTimeSec: Double = 0
    @Published var durationSec: Double = 0
    @Published var isSeeking: Bool = false

    @Published var audioTracks: [(index: Int32, name: String)] = []
    @Published var subtitleTracks: [(index: Int32, name: String)] = []
    @Published var currentAudioIndex: Int32 = -1
    @Published var currentSubIndex: Int32 = -1
    @Published var isAspectFilled: Bool = false

    private var timer: Timer?

    init() {
        startTelemetryTimer()
    }

    deinit {
        timer?.invalidate()
    }

    private func startTelemetryTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.useNativeAVPlayer, let av = self.avPlayer {
                self.isPlaying = (av.rate > 0 && av.error == nil)
                if !self.isSeeking {
                    let cur = CMTimeGetSeconds(av.currentTime())
                    if cur.isFinite && cur >= 0 { self.currentTimeSec = cur }
                    if let durItem = av.currentItem?.duration {
                        let d = CMTimeGetSeconds(durItem)
                        if d.isFinite && d > 0 { self.durationSec = d }
                    }
                }
            } else {
                self.isPlaying = self.vlcPlayer.isPlaying
                if !self.isSeeking {
                    let curMs = Double(self.vlcPlayer.time.intValue)
                    if curMs >= 0 { self.currentTimeSec = curMs / 1000.0 }
                    if let mediaLen = self.vlcPlayer.media?.length.intValue, mediaLen > 0 {
                        self.durationSec = Double(mediaLen) / 1000.0
                    }
                }
                self.refreshVLCTracksIfNeeded()
            }
        }
    }

    private func refreshVLCTracksIfNeeded() {
        if let names = vlcPlayer.audioTrackNames as? [String],
           let indexes = vlcPlayer.audioTrackIndexes as? [NSNumber],
           names.count == indexes.count {
            var list: [(Int32, String)] = []
            for i in 0..<names.count {
                list.append((indexes[i].int32Value, names[i]))
            }
            if list.count != audioTracks.count {
                audioTracks = list
                currentAudioIndex = vlcPlayer.currentAudioTrackIndex
            }
        }
        if let sNames = vlcPlayer.videoSubTitlesNames as? [String],
           let sIndexes = vlcPlayer.videoSubTitlesIndexes as? [NSNumber],
           sNames.count == sIndexes.count {
            var sList: [(Int32, String)] = []
            for i in 0..<sNames.count {
                sList.append((sIndexes[i].int32Value, sNames[i]))
            }
            if sList.count != subtitleTracks.count {
                subtitleTracks = sList
                currentSubIndex = vlcPlayer.currentVideoSubTitleIndex
            }
        }
    }

    func play(item: MediaItem) {
        let cleaned = item.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawURL = URL(string: cleaned) else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)

        stopAll()
        currentTitle = item.title
        isLiveStream = (item.kind == .live)
        currentTimeSec = 0
        durationSec = 0
        audioTracks = []
        subtitleTracks = []

        let low = cleaned.lowercased()
        // Usa AVPlayer nativo (con UI Liquid Glass di sistema iOS 27) per HLS (.m3u8) e file MP4/MOV nativi
        let supportsNativeAV = low.contains(".m3u8") || low.hasSuffix(".mp4") || low.hasSuffix(".mov") || low.hasSuffix(".m4v")

        if supportsNativeAV {
            useNativeAVPlayer = true
            let headers = ["User-Agent": "VLC/3.0.20 LibVLC/3.0.20"]
            let asset = AVURLAsset(url: rawURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let pItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: pItem)
            player.allowsExternalPlayback = true
            self.avPlayer = player
            player.play()
            isPlaying = true
        } else {
            // Per flussi Live MPEG-TS (.ts) o MKV/AVI usa MobileVLCKit con HUD Liquid Glass iOS 27
            useNativeAVPlayer = false
            let media = VLCMedia(url: rawURL)
            media.addOptions([
                "network-caching": 1500,
                "live-caching": 1500,
                "clock-jitter": 0,
                "clock-synchro": 0,
                "http-user-agent": "VLC/3.0.20 LibVLC/3.0.20",
                "http-reconnect": true
            ])
            vlcPlayer.media = media
            vlcPlayer.play()
            isPlaying = true
        }
    }

    func togglePlayPause() {
        if useNativeAVPlayer, let av = avPlayer {
            if av.rate > 0 {
                av.pause()
                isPlaying = false
            } else {
                av.play()
                isPlaying = true
            }
        } else {
            if vlcPlayer.isPlaying {
                vlcPlayer.pause()
                isPlaying = false
            } else {
                vlcPlayer.play()
                isPlaying = true
            }
        }
    }

    func jump(seconds: Double) {
        if useNativeAVPlayer, let av = avPlayer {
            let cur = CMTimeGetSeconds(av.currentTime())
            let target = CMTime(seconds: max(0, cur + seconds), preferredTimescale: 600)
            av.seek(to: target)
        } else {
            if seconds < 0 {
                vlcPlayer.jumpBackward(Int32(abs(seconds)))
            } else {
                vlcPlayer.jumpForward(Int32(seconds))
            }
        }
    }

    func seek(toSeconds: Double) {
        if useNativeAVPlayer, let av = avPlayer {
            let target = CMTime(seconds: max(0, toSeconds), preferredTimescale: 600)
            av.seek(to: target)
        } else if durationSec > 0 {
            let pos = Float(min(max(toSeconds / durationSec, 0), 1))
            vlcPlayer.position = pos
        }
    }

    func selectAudioTrack(_ idx: Int32) {
        vlcPlayer.currentAudioTrackIndex = idx
        currentAudioIndex = idx
    }

    func selectSubtitleTrack(_ idx: Int32) {
        vlcPlayer.currentVideoSubTitleIndex = idx
        currentSubIndex = idx
    }

    func toggleAspectFill() {
        isAspectFilled.toggle()
        if isAspectFilled {
            let screen = UIScreen.main.bounds
            let ratio = "\(Int(screen.width)):\(Int(screen.height))"
            vlcPlayer.videoAspectRatio = UnsafeMutablePointer<Int8>(mutating: (ratio as NSString).utf8String)
        } else {
            vlcPlayer.videoAspectRatio = nil
        }
    }

    func stopAll() {
        avPlayer?.pause()
        avPlayer = nil
        vlcPlayer.stop()
        isPlaying = false
    }
}

// Wrapper ufficiale AVPlayerViewController di iOS (rende il player nativo iOS 27 con Liquid Glass, AirPlay, PiP e X di sistema)
struct NativeIOSPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    let showsPlaybackControls: Bool
    var onDismissFullscreen: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = showsPlaybackControls
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.videoGravity = .resizeAspect
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
        uiViewController.showsPlaybackControls = showsPlaybackControls
    }
}

struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player.drawable = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if player.drawable as? UIView !== uiView {
            player.drawable = uiView
        }
    }
}

// HUD Fullscreen Liquid Glass stile iOS 27 (rispetta Safe Area, X circolare pulita, scrubber, audio/sub)
struct LiquidGlassFullscreenHUD: View {
    @ObservedObject var controller: HybridPlayerController
    let onClose: () -> Void
    @State private var showControls: Bool = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Area trasparente per mostrare/nascondere i controlli al tap
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showControls.toggle()
                    }
                    scheduleAutoHide()
                }

            if showControls {
                VStack {
                    // Barra superiore ancorata sotto la Status Bar / Dynamic Island (Safe Area rispettata)
                    HStack(spacing: 12) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Circle().fill(Color.white.opacity(0.08)))
                                        .overlay(
                                            Circle().strokeBorder(
                                                LinearGradient(
                                                    colors: [Color.white.opacity(0.45), Color.white.opacity(0.12)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                        )
                                )
                                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)

                        Text(controller.currentTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8))
                            )

                        Spacer()

                        // Menu tracce Audio e Sottotitoli in stile Liquid Glass
                        if !controller.audioTracks.isEmpty || !controller.subtitleTracks.isEmpty {
                            Menu {
                                if !controller.audioTracks.isEmpty {
                                    Section("Audio") {
                                        ForEach(controller.audioTracks, id: \.index) { tr in
                                            Button {
                                                controller.selectAudioTrack(tr.index)
                                            } label: {
                                                if tr.index == controller.currentAudioIndex {
                                                    Label(tr.name, systemImage: "checkmark")
                                                } else {
                                                    Text(tr.name)
                                                }
                                            }
                                        }
                                    }
                                }
                                if !controller.subtitleTracks.isEmpty {
                                    Section("Sottotitoli") {
                                        ForEach(controller.subtitleTracks, id: \.index) { sub in
                                            Button {
                                                controller.selectSubtitleTrack(sub.index)
                                            } label: {
                                                if sub.index == controller.currentSubIndex {
                                                    Label(sub.name, systemImage: "checkmark")
                                                } else {
                                                    Text(sub.name)
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "captions.bubble")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.9))
                                    )
                            }
                        }

                        // Pulsante Adatta / Riempi schermo
                        Button {
                            controller.toggleAspectFill()
                            scheduleAutoHide()
                        } label: {
                            Image(systemName: controller.isAspectFilled ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.9))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()

                    // Dock inferiore Liquid Glass completo (Scrubber + Controlli traslucidi iOS 27)
                    VStack(spacing: 12) {
                        if controller.durationSec > 1 && !controller.isLiveStream {
                            VStack(spacing: 4) {
                                Slider(
                                    value: Binding(
                                        get: { controller.currentTimeSec },
                                        set: { newVal in
                                            controller.isSeeking = true
                                            controller.currentTimeSec = newVal
                                        }
                                    ),
                                    in: 0...max(controller.durationSec, 1),
                                    onEditingChanged: { editing in
                                        if !editing {
                                            controller.seek(toSeconds: controller.currentTimeSec)
                                            controller.isSeeking = false
                                            scheduleAutoHide()
                                        }
                                    }
                                )
                                .tint(.white)

                                HStack {
                                    Text(formatTime(controller.currentTimeSec))
                                    Spacer()
                                    Text("-\(formatTime(max(0, controller.durationSec - controller.currentTimeSec)))")
                                }
                                .font(.caption2.monospacedDigit().weight(.medium))
                                .foregroundColor(.white.opacity(0.8))
                            }
                        } else {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("LIVE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.white.opacity(0.9))
                                Spacer()
                            }
                        }

                        HStack(spacing: 34) {
                            Button {
                                controller.jump(seconds: -15)
                                scheduleAutoHide()
                            } label: {
                                Image(systemName: "gobackward.15")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)

                            Button {
                                controller.togglePlayPause()
                                scheduleAutoHide()
                            } label: {
                                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle()
                                            .fill(Color.white.opacity(0.16))
                                            .overlay(Circle().strokeBorder(Color.white.opacity(0.32), lineWidth: 1))
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                controller.jump(seconds: 15)
                                scheduleAutoHide()
                            } label: {
                                Image(systemName: "goforward.15")
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.10), Color.white.opacity(0.24)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && !controller.isSeeking {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showControls = false
                    }
                }
            }
        }
    }

    private func formatTime(_ sec: Double) -> String {
        guard sec.isFinite && sec >= 0 else { return "00:00" }
        let total = Int(sec)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: CatalogStore
    @EnvironmentObject var downloader: DownloadService
    @StateObject private var playerCtrl = HybridPlayerController()

    @State private var selectedTab: AppTab = .home
    @State private var currentItem: MediaItem?
    @State private var isFullScreen: Bool = false
    @State private var showDownloads: Bool = false
    @State private var expandedGroup: String?
    @State private var downloadBannerText: String?

    var body: some View {
        ZStack {
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

            if selectedTab == .settings && !isFullScreen {
                SettingsTabView()
                    .environmentObject(store)
                    .environmentObject(downloader)
                    .padding(.bottom, 82)
            } else {
                VStack(spacing: 10) {
                    if !isFullScreen {
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
                    }

                    // Superficie Video Unica (Nativo iOS AVPlayerViewController per HLS/MP4 + VLCKit con HUD Liquid Glass iOS 27 per Live .ts)
                    ZStack {
                        RoundedRectangle(cornerRadius: isFullScreen ? 0 : 16, style: .continuous)
                            .fill(Color.black)
                            .overlay(
                                RoundedRectangle(cornerRadius: isFullScreen ? 0 : 16, style: .continuous)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isFullScreen ? 0 : 0.42), Color.white.opacity(isFullScreen ? 0 : 0.10), Color.white.opacity(isFullScreen ? 0 : 0.24)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: isFullScreen ? 0 : 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(isFullScreen ? 0 : 0.45), radius: 12, x: 0, y: 6)

                        if currentItem != nil {
                            if playerCtrl.useNativeAVPlayer, let av = playerCtrl.avPlayer {
                                NativeIOSPlayerView(player: av, showsPlaybackControls: isFullScreen)
                                    .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 15, style: .continuous))
                                    .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
                            } else {
                                VLCVideoSurface(player: playerCtrl.vlcPlayer)
                                    .clipShape(RoundedRectangle(cornerRadius: isFullScreen ? 0 : 15, style: .continuous))
                                    .ignoresSafeArea(isFullScreen ? .all : [], edges: .all)
                            }
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "play.tv")
                                    .font(.title2)
                                    .foregroundColor(.white.opacity(0.35))
                                Text("Seleziona un canale, film o serie")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        // In Fullscreen: se è attivo AVPlayerViewController nativo iOS 27, usa i controlli nativi Apple (tranne un pulsante X SafeArea in basso/angolo se serve);
                        // se è attivo VLCKit (Live .ts), mostra l'HUD completo Liquid Glass iOS 27 dentro la Safe Area!
                        if isFullScreen {
                            if playerCtrl.useNativeAVPlayer {
                                VStack {
                                    HStack {
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                isFullScreen = false
                                            }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                                .frame(width: 38, height: 38)
                                                .background(
                                                    Circle()
                                                        .fill(.ultraThinMaterial)
                                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)
                                    Spacer()
                                }
                            } else {
                                LiquidGlassFullscreenHUD(controller: playerCtrl) {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        isFullScreen = false
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: isFullScreen ? .infinity : 210)
                    .padding(.horizontal, isFullScreen ? 0 : 12)

                    if !isFullScreen {
                        // Pillola Controlli Player Liquid Glass (modalità finestra)
                        HStack(spacing: 10) {
                            Button {
                                playerCtrl.togglePlayPause()
                            } label: {
                                Image(systemName: playerCtrl.isPlaying ? "pause.fill" : "play.fill")
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

                            Button("-15s") { playerCtrl.jump(seconds: -15) }
                                .buttonStyle(LiquidGlassPillButtonStyle())

                            Button("+15s") { playerCtrl.jump(seconds: 15) }
                                .buttonStyle(LiquidGlassPillButtonStyle())

                            Button {
                                playerCtrl.stopAll()
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
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    isFullScreen = true
                                }
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
            }

            // Menu Flottante Liquid Glass bloccato in basso (ignorando la tastiera iOS)
            if !isFullScreen {
                VStack {
                    Spacer()
                    LiquidGlassFloatingTabBar(selectedTab: $selectedTab)
                        .onChange(of: selectedTab) { newTab in
                            expandedGroup = nil
                            if newTab != .settings {
                                store.selectedCategory = newTab.mediaKind
                                store.onCategoryChanged()
                            }
                        }
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .sheet(isPresented: $showDownloads) {
            DownloadsSheetView()
                .environmentObject(downloader)
        }
    }

    private func channelRow(_ item: MediaItem) -> some View {
        HStack(spacing: 8) {
            Button {
                currentItem = item
                playerCtrl.play(item: item)
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
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        .scrollDismissesKeyboard(.interactively)
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
