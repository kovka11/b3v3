import SwiftUI
import UIKit

// MARK: - Kedvencek

struct Favorite: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
}

final class FavoritesStore: ObservableObject {
    @Published private(set) var items: [Favorite] = []
    private let key = "goldengate.favorites"

    init() {
        load()
    }

    func contains(_ url: URL) -> Bool {
        items.contains { $0.url == url.absoluteString }
    }

    func add(title: String, url: URL) {
        guard !contains(url) else { return }
        items.insert(Favorite(title: title, url: url.absoluteString), at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let decoded = try? JSONDecoder().decode([Favorite].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Reklámblokkoló szabályok

enum AdBlockRules {
    /// Harmadik féltől érkező reklám- és felugró-hálózatok
    static let domains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com",
        "exoclick.com", "exosrv.com", "exdynsrv.com", "realsrv.com", "magsrv.com",
        "trafficjunky.net", "juicyads.com", "adsterra.com", "popads.net",
        "popcash.net", "propellerads.com", "clickadu.com", "hilltopads.net",
        "trafficstars.com", "tsyndicate.com", "ero-advertising.com", "adnxs.com",
        "a-ads.com", "adspyglass.com", "plugrush.com", "crakrevenue.com",
        "onclickads.net", "pushwhy.com"
    ]

    static var json: String {
        let rules = domains.map { domain -> String in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\\\.")
            return "{\"trigger\":{\"url-filter\":\"\(escaped)\",\"load-type\":[\"third-party\"]},\"action\":{\"type\":\"block\"}}"
        }
        return "[" + rules.joined(separator: ",") + "]"
    }
}
