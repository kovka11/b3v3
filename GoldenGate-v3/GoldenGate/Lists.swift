import SwiftUI

// MARK: - Videó linkek

struct VideoLink: Identifiable, Equatable {
    let url: URL
    var size: Int64?

    var id: String { url.absoluteString }
    var ext: String { url.pathExtension.lowercased() }
    var isPlayable: Bool { ["mp4", "m4v", "mov"].contains(ext) }

    var name: String {
        let decoded = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return decoded.isEmpty ? url.absoluteString : decoded
    }
}

func formattedSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

/// Lekérdezi egy link fájlméretét anélkül, hogy letöltené a fájlt.
enum LinkInspector {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static func size(of url: URL, headers: [String: String]) async -> Int64? {
        if let size = await probe(url, method: "HEAD", headers: headers) {
            return size
        }
        return await probe(url, method: "GET", headers: headers)
    }

    private static func probe(_ url: URL, method: String, headers: [String: String]) async -> Int64? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if method == "GET" {
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() } // a tartalmat nem töltjük le

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last,
               let value = Int64(total) {
                return value
            }
            if let length = http.value(forHTTPHeaderField: "Content-Length"),
               let value = Int64(length), value > 1 {
                return value
            }
            return nil
        } catch {
            return nil
        }
    }
}

final class VideoLinksModel: ObservableObject {
    @Published var links: [VideoLink]
    private let urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
        self.links = urls.map { VideoLink(url: $0) }
    }

    /// Fájlméretek betöltése, egyszerre legfeljebb 4 kéréssel.
    func loadSizes(auth: AuthContext) async {
        var index = 0
        while index < urls.count {
            if Task.isCancelled { return }

            let chunk = Array(urls[index..<min(index + 4, urls.count)])
            let prepared = chunk.map { ($0, auth.headers(for: $0)) }

            var results: [(URL, Int64?)] = []
            await withTaskGroup(of: (URL, Int64?).self) { group in
                for (url, headers) in prepared {
                    group.addTask {
                        (url, await LinkInspector.size(of: url, headers: headers))
                    }
                }
                for await result in group {
                    results.append(result)
                }
            }

            let snapshot = results
            await MainActor.run {
                for (url, size) in snapshot {
                    if let position = self.links.firstIndex(where: { $0.url == url }) {
                        self.links[position].size = size
                    }
                }
            }
            index += 4
        }
    }
}

struct VideoLinksView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case all = "Mind"
        case mp4 = "MP4"
        case avi = "AVI"
        var id: String { rawValue }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case found = "Oldalon látható sorrend"
        case name = "Név szerint"
        case size = "Méret szerint (nagy elöl)"
        var id: String { rawValue }
    }

    @StateObject private var model: VideoLinksModel
    let auth: AuthContext
    let onPlay: (URL) -> Void
    let onDownload: (URL) -> Void
    let onOpenPage: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var kind: Kind = .all
    @State private var sort: Sort = .found
    @State private var started: Set<String> = []

    init(links: [URL],
         auth: AuthContext,
         onPlay: @escaping (URL) -> Void,
         onDownload: @escaping (URL) -> Void,
         onOpenPage: @escaping (URL) -> Void) {
        _model = StateObject(wrappedValue: VideoLinksModel(urls: links))
        self.auth = auth
        self.onPlay = onPlay
        self.onDownload = onDownload
        self.onOpenPage = onOpenPage
    }

    private var visible: [VideoLink] {
        var list = model.links

        switch kind {
        case .all: break
        case .mp4: list = list.filter { $0.ext == "mp4" }
        case .avi: list = list.filter { $0.ext == "avi" }
        }

        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !text.isEmpty {
            list = list.filter { $0.url.absoluteString.lowercased().contains(text) }
        }

        switch sort {
        case .found:
            break
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            list.sort { ($0.size ?? -1) > ($1.size ?? -1) }
        }
        return list
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Picker("Típus", selection: $kind) {
                        ForEach(Kind.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if model.links.isEmpty {
                    Text("Ezen az oldalon nem találtam .mp4 vagy .avi linket. Ha a videó csak lejátszáskor töltődik be, indítsd el, majd nyisd meg újra ezt a listát.")
                        .foregroundStyle(.secondary)
                } else if visible.isEmpty {
                    Text("Nincs a szűrésnek megfelelő link.")
                        .foregroundStyle(.secondary)
                }

                ForEach(visible) { link in
                    row(link)
                }
            }
            .searchable(text: $query, prompt: "Keresés a linkek között")
            .navigationTitle("Videó linkek (\(model.links.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Rendezés", selection: $sort) {
                            ForEach(Sort.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kész") { dismiss() }
                }
            }
            .task {
                await model.loadSizes(auth: auth)
            }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ link: VideoLink) -> some View {
        HStack(spacing: 12) {
            Button {
                primaryAction(link)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.name)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(link.ext.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Gold.main.opacity(0.25), in: Capsule())
                        if let size = link.size {
                            Text(formattedSize(size))
                        }
                        Text(link.url.host ?? "")
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if started.contains(link.id) {
                        Label("Letöltés elindult", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundColor(Gold.main)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Menu {
                if link.isPlayable {
                    Button {
                        onPlay(link.url)
                    } label: {
                        Label("Lejátszás", systemImage: "play.fill")
                    }
                }
                Button {
                    startDownload(link)
                } label: {
                    Label("Letöltés", systemImage: "arrow.down.circle")
                }
                Button {
                    onOpenPage(link.url)
                    dismiss()
                } label: {
                    Label("Megnyitás az oldalban", systemImage: "safari")
                }
                Divider()
                Button {
                    UIPasteboard.general.string = link.url.absoluteString
                } label: {
                    Label("Link másolása", systemImage: "doc.on.doc")
                }
                Button {
                    UIHelper.presentShareSheet(items: [link.url])
                } label: {
                    Label("Link megosztása", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
            }
            .buttonStyle(.borderless)
        }
    }

    /// Koppintásra: ami lejátszható, azt lejátssza, a többit (pl. .avi) letölti.
    private func primaryAction(_ link: VideoLink) {
        if link.isPlayable {
            onPlay(link.url)
        } else {
            startDownload(link)
        }
    }

    private func startDownload(_ link: VideoLink) {
        started.insert(link.id)
        onDownload(link.url)
    }
}

// MARK: - Letöltések

struct DownloadsView: View {
    @ObservedObject var manager: DownloadManager
    let onPlay: (URL, String) -> Void
    let onRetry: (DownloadItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if manager.items.isEmpty {
                    Text("Még nincs letöltés. A videólinkek listájában (🎞) a ⋯ menüből indíthatsz letöltést.")
                        .foregroundStyle(.secondary)
                }

                ForEach(manager.items) { item in
                    row(item)
                }
                .onDelete { offsets in
                    manager.delete(at: offsets)
                }

                if !manager.items.isEmpty {
                    Section {
                        Text("Összesen: \(manager.totalSizeText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Letöltések")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kész") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func row(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .lineLimit(2)

            switch item.status {
            case .downloading:
                ProgressView(value: item.progress)
                Text(progressText(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .failed:
                HStack {
                    Text("Sikertelen letöltés")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Újra") { onRetry(item) }
                        .buttonStyle(.borderless)
                }

            case .finished:
                Text(finishedText(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            open(item)
        }
        .contextMenu {
            if item.status == .finished {
                Button {
                    UIHelper.presentShareSheet(items: [manager.fileURL(for: item)])
                } label: {
                    Label("Megosztás / Mentés a Fájlokba", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                manager.remove(item)
            } label: {
                Label("Törlés", systemImage: "trash")
            }
        }
    }

    private func open(_ item: DownloadItem) {
        guard item.status == .finished else { return }
        let file = manager.fileURL(for: item)
        if item.isPlayable {
            onPlay(file, item.name)
        } else {
            UIHelper.presentShareSheet(items: [file])
        }
    }

    private func progressText(_ item: DownloadItem) -> String {
        if item.totalBytes > 0 {
            let percent = Int(item.progress * 100)
            return "\(formattedSize(item.receivedBytes)) / \(formattedSize(item.totalBytes)) (\(percent)%)"
        }
        return formattedSize(item.receivedBytes)
    }

    private func finishedText(_ item: DownloadItem) -> String {
        let base = "\(item.ext.uppercased()) · \(formattedSize(item.totalBytes))"
        if item.isPlayable {
            return base + " · koppints a lejátszáshoz"
        }
        return base + " · koppints a megosztáshoz (pl. VLC-vel nyitható)"
    }
}
