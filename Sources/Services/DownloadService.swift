import Foundation

@MainActor
final class DownloadService: ObservableObject {
    @Published var tasks: [DownloadTaskItem] = []
    private var currentTask: URLSessionDownloadTask?

    var activeCount: Int {
        tasks.filter { !$0.isCompleted && !$0.isFailed }.count
    }

    func enqueue(title: String, urlString: String) {
        let item = DownloadTaskItem(title: title, url: urlString)
        tasks.append(item)
        startNextIfIdle()
    }

    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        tasks.removeAll { !$0.isCompleted }
    }

    func clearCompleted() {
        tasks.removeAll { $0.isCompleted || $0.isFailed }
    }

    private func startNextIfIdle() {
        guard currentTask == nil, let idx = tasks.firstIndex(where: { !$0.isCompleted && !$0.isFailed }) else { return }
        guard let url = URL(string: tasks[idx].url) else {
            tasks[idx].isFailed = true
            tasks[idx].status = "URL non valido"
            startNextIfIdle()
            return
        }

        tasks[idx].status = "In download..."
        let title = tasks[idx].title

        currentTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.currentTask = nil
                if let tempURL = tempURL, error == nil {
                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let safeName = title.replacingOccurrences(of: "/", with: "-") + ".mp4"
                    let dest = docs.appendingPathComponent(safeName)
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.moveItem(at: tempURL, to: dest)
                    if let i = self.tasks.firstIndex(where: { $0.title == title && !$0.isCompleted }) {
                        self.tasks[i].progress = 1.0
                        self.tasks[i].isCompleted = true
                        self.tasks[i].status = "Completato"
                        self.tasks[i].localURL = dest
                    }
                } else if let i = self.tasks.firstIndex(where: { $0.title == title && !$0.isCompleted }) {
                    self.tasks[i].isFailed = true
                    self.tasks[i].status = "Errore"
                }
                self.startNextIfIdle()
            }
        }
        currentTask?.resume()
    }
}
