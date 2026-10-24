import SwiftUI

struct OfflineView: View {
    let isOnline: Bool
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isOnline ? "exclamationmark.triangle" : "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(isOnline ? "Az oldal most nem érhető el" : "Nincs internetkapcsolat")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Ellenőrizd a kapcsolatot, majd próbáld újra.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Label("Újrapróbálás", systemImage: "arrow.clockwise")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Gold.light)
                Text("GoldenGate")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Button(action: unlock) {
                    Label("Feloldás", systemImage: "faceid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct IncognitoBadge: View {
    var body: some View {
        Label("Inkognitó", systemImage: "eye.slash")
            .font(.caption.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Gold.main, in: Capsule())
    }
}

/// Vészkijelző: teljes képernyős, ártalmatlan jegyzetek képernyő.
/// Visszatérés: a "Jegyzetek" címet nyomd hosszan (másfél másodpercig), majd azonosítsd magad.
struct NeutralCover: View {
    let onExit: () -> Void

    private let notes: [(title: String, text: String)] = [
        ("Bevásárlólista", "tej, kenyér, tojás, alma, kávé"),
        ("Teendők", "számla befizetése, időpont egyeztetése"),
        ("Receptötletek", "rakott krumpli, gyümölcssaláta"),
        ("Könyvek", "olvasási lista a nyárra"),
        ("Edzés", "kedd, csütörtök, szombat")
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(notes, id: \.title) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .font(.headline)
                        Text(note.text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Jegyzetek")
                        .font(.headline)
                        .onLongPressGesture(minimumDuration: 1.5) {
                            onExit()
                        }
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(Color(.systemBackground).ignoresSafeArea())
        .tint(.orange)
    }
}

struct FavoritesView: View {
    @ObservedObject var store: FavoritesStore
    let open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if store.items.isEmpty {
                    Text("Még nincs kedvenc. A ⋯ menüben mentheted az aktuális oldalt.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.items) { item in
                    Button {
                        if let url = URL(string: item.url) {
                            open(url)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundColor(.primary)
                            Text(item.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .onDelete { offsets in
                    store.remove(at: offsets)
                }
            }
            .navigationTitle("Kedvencek")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kész") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
