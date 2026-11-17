import Foundation

@MainActor
final class DownloadService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var tasks: [DownloadTaskItem] = []
    private var session: URLSession!
    private var activeTask: URLSessionDownloadTask?
    private var activeTaskID: UUID?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "VLC/3.0.20 LibVLC/3.0.20",
            "Accept": "*/*"
        ]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    var activeCount: Int {
        tasks.filter { !$0.isCompleted && !$0.isFailed }.count
    }

    func enqueue(title: String, urlString: String) {
        let item = DownloadTaskItem(title: title, url: urlString)
        tasks.append(item)
        startNextIfIdle()
    }

    func cancelAll() {
        activeTask?.cancel()
        activeTask = nil
        activeTaskID = nil
        tasks.removeAll { !$0.isCompleted }
    }

    func clearCompleted() {
        tasks.removeAll { $0.isCompleted || $0.isFailed }
    }

    private func startNextIfIdle() {
        guard activeTask == nil, let idx = tasks.firstIndex(where: { !$0.isCompleted && !$0.isFailed }) else { return }
        let rawUrl = tasks[idx].url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: rawUrl) else {
            tasks[idx].isFailed = true
            tasks[idx].status = "URL non valido"
            startNextIfIdle()
            return
        }

        if rawUrl.lowercased().hasSuffix(".m3u8") {
            tasks[idx].isFailed = true
            tasks[idx].status = "Flusso live HLS (.m3u8) non scaricabile direttamente"
            startNextIfIdle()
            return
        }

        tasks[idx].status = "Connessione..."
        activeTaskID = tasks[idx].id
        var req = URLRequest(url: url)
        req.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")

        let task = session.downloadTask(with: req)
        activeTask = task
        task.resume()
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            guard let id = self.activeTaskID, let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            let mb = Double(totalBytesWritten) / (1024.0 * 1024.0)
            if totalBytesExpectedToWrite > 0 {
                let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                self.tasks[idx].progress = pct
                self.tasks[idx].status = String(format: "Scaricamento: %.0f%% (%.1f MB)", pct * 100, mb)
            } else {
                self.tasks[idx].status = String(format: "Scaricamento: %.1f MB", mb)
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.copyItem(at: location, to: tempCopy)

        Task { @MainActor in
            guard let id = self.activeTaskID, let idx = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            let title = self.tasks[idx].title
            let sourceExt = URL(string: self.tasks[idx].url)?.pathExtension ?? ""
            let ext = ["mp4", "mkv", "avi", "ts", "mov"].contains(sourceExt.lowercased()) ? sourceExt : "mp4"

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let safeName = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".\(ext)"
            let dest = docs.appendingPathComponent(safeName)

            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: tempCopy, to: dest)
                self.tasks[idx].progress = 1.0
                self.tasks[idx].isCompleted = true
                self.tasks[idx].status = "Completato (\(safeName))"
                self.tasks[idx].localURL = dest
            } catch {
                self.tasks[idx].isFailed = true
                self.tasks[idx].status = "Errore salvataggio: \(error.localizedDescription)"
            }

            self.activeTask = nil
            self.activeTaskID = nil
            self.startNextIfIdle()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        Task { @MainActor in
            if let id = self.activeTaskID, let idx = self.tasks.firstIndex(where: { $0.id == id }) {
                self.tasks[idx].isFailed = true
                self.tasks[idx].status = "Errore: \(error.localizedDescription)"
            }
            self.activeTask = nil
            self.activeTaskID = nil
            self.startNextIfIdle()
        }
    }
}
