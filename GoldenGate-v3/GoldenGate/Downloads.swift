import Foundation
import UIKit

// MARK: - Belépett munkamenet adatai (süti, böngésző-azonosító)

/// A WebView-ból átvett süti- és fejlécadatok. Ezzel tölt le és játszik le az app úgy,
/// mintha a belépett fiókod kérné a fájlt.
struct AuthContext {
    var cookies: [HTTPCookie] = []
    var userAgent: String = ""

    func headers(for url: URL) -> [String: String] {
        var result: [String: String] = ["Referer": startURL.absoluteString]
        if !userAgent.isEmpty {
            result["User-Agent"] = userAgent
        }
        let host = (url.host ?? "").lowercased()
        let matching = cookies.filter { cookie in
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") {
                domain.removeFirst()
            }
            return host == domain || host.hasSuffix("." + domain)
        }
        for (key, value) in HTTPCookie.requestHeaderFields(with: matching) {
            result[key] = value
        }
        return result
    }
}

// MARK: - Letöltések

struct DownloadItem: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case downloading
        case finished
        case failed
    }

    var id = UUID()
    var url: String
    var name: String
    var localName: String?
    var status: Status = .downloading
    var totalBytes: Int64 = 0
    var receivedBytes: Int64 = 0
    var date = Date()

    var progress: Double {
        totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : 0
    }

    var ext: String {
        URL(fileURLWithPath: localName ?? name).pathExtension.lowercased()
    }

    var isPlayable: Bool {
        ["mp4", "m4v", "mov"].contains(ext)
    }
}

/// Háttérben is futó letöltéskezelő. A fájlok az app saját mappájába kerülnek.
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    static var backgroundCompletionHandler: (() -> Void)?

    @Published private(set) var items: [DownloadItem] = []

    private static let storeKey = "goldengate.downloads"
    private static let sessionID = "hu.goldengate.app.downloads"

    private let folder: URL
    private var session: URLSession!
    private var lastTick: [UUID: Date] = [:] // csak a delegate sorában használjuk

    private override init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Downloads", isDirectory: true)
        super.init()

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()

        let config = URLSessionConfiguration.background(withIdentifier: DownloadManager.sessionID)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        reconcile()
    }

    // MARK: Nyilvános műveletek

    /// Letöltés indítása. Hamis, ha ez a fájl már a listán van.
    @discardableResult
    func start(url: URL, headers: [String: String]) -> Bool {
        if items.contains(where: { $0.url == url.absoluteString && $0.status != .failed }) {
            return false
        }

        let id = UUID()
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        var item = DownloadItem(id: id, url: url.absoluteString, name: DownloadManager.displayName(for: url))
        item.localName = DownloadManager.localFileName(id: id, url: url)
        items.insert(item, at: 0)
        save()

        let task = session.downloadTask(with: request)
        task.taskDescription = id.uuidString
        task.resume()
        return true
    }

    func retry(_ item: DownloadItem, headers: [String: String]) {
        guard let url = URL(string: item.url) else { return }
        remove(item)
        start(url: url, headers: headers)
    }

    func delete(at offsets: IndexSet) {
        let removed = offsets.map { items[$0] }
        for item in removed {
            remove(item)
        }
    }

    func remove(_ item: DownloadItem) {
        cancelTask(id: item.id)
        if let local = item.localName {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(local))
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    func fileURL(for item: DownloadItem) -> URL {
        folder.appendingPathComponent(item.localName ?? item.id.uuidString)
    }

    var totalSizeText: String {
        let total = items.filter { $0.status == .finished }.reduce(Int64(0)) { $0 + $1.totalBytes }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    // MARK: Segédek

    static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return name.isEmpty ? "videó" : name
    }

    static func localFileName(id: UUID, url: URL) -> String {
        let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension.lowercased()
        return "\(id.uuidString).\(ext)"
    }

    private func cancelTask(id: UUID) {
        session.getAllTasks { tasks in
            tasks.first(where: { $0.taskDescription == id.uuidString })?.cancel()
        }
    }

    /// Újraindításkor: ami "töltődik", de nincs hozzá futó feladat, az megszakadt.
    private func reconcile() {
        session.getAllTasks { [weak self] tasks in
            let live = Set(tasks.compactMap { $0.taskDescription })
            DispatchQueue.main.async {
                guard let self else { return }
                var changed = false
                for index in self.items.indices {
                    let item = self.items[index]
                    if item.status == .downloading && !live.contains(item.id.uuidString) {
                        self.items[index].status = .failed
                        changed = true
                    }
                }
                if changed {
                    self.save()
                }
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: DownloadManager.storeKey),
            let decoded = try? JSONDecoder().decode([DownloadItem].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: DownloadManager.storeKey)
        }
    }
}

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let idString = downloadTask.taskDescription, let id = UUID(uuidString: idString) else { return }

        let now = Date()
        if let last = lastTick[id], now.timeIntervalSince(last) < 0.3 { return }
        lastTick[id] = now

        DispatchQueue.main.async {
            guard let index = self.items.firstIndex(where: { $0.id == id }) else { return }
            self.items[index].receivedBytes = totalBytesWritten
            self.items[index].totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : 0
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard
            let idString = downloadTask.taskDescription,
            let id = UUID(uuidString: idString),
            let url = downloadTask.originalRequest?.url
        else { return }

        lastTick[id] = nil

        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            DispatchQueue.main.async {
                self.update(id) { $0.status = .failed }
            }
            return
        }

        let destination = folder.appendingPathComponent(DownloadManager.localFileName(id: id, url: url))
        try? FileManager.default.removeItem(at: destination)

        do {
            try FileManager.default.moveItem(at: location, to: destination)

            var target = destination
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)

            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

            DispatchQueue.main.async {
                self.update(id) {
                    $0.status = .finished
                    $0.localName = destination.lastPathComponent
                    $0.totalBytes = size
                    $0.receivedBytes = size
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.update(id) { $0.status = .failed }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard
            let error,
            let idString = task.taskDescription,
            let id = UUID(uuidString: idString)
        else { return }

        if (error as NSError).code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            self.update(id) { $0.status = .failed }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            DownloadManager.backgroundCompletionHandler?()
            DownloadManager.backgroundCompletionHandler = nil
        }
    }
}
