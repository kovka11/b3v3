import SwiftUI

/// Az app által betöltött oldal. Ha változik a cím, csak ezt kell átírni.
let startURL = URL(string: "https://goldengate.hu")!

struct ContentView: View {
    @EnvironmentObject private var appLock: AppLock
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var web = WebState()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var favorites = FavoritesStore()
    @ObservedObject private var downloads = DownloadManager.shared
    @AppStorage("goldengate.shakePanic") private var shakePanic = true

    @State private var showFavorites = false
    @State private var showDownloads = false
    @State private var showVideos = false
    @State private var confirmClear = false
    @State private var videoLinks: [URL] = []
    @State private var authContext = AuthContext()
    @State private var player: PlayerItem?
    @State private var isPanic = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            // Az állapotsor mögötti szín az oldal témaszínét követi
            (web.themeColor ?? Color(.systemBackground))
                .ignoresSafeArea()

            mainColumn

            if appLock.isLocked {
                LockView {
                    appLock.unlock()
                }
            }

            if isPanic {
                NeutralCover {
                    appLock.authenticate(reason: "Visszatérés a GoldenGate-hez") { success in
                        if success {
                            isPanic = false
                        }
                    }
                }
            }
        }
        .tint(Gold.main)
        .sheet(isPresented: $showFavorites) {
            FavoritesView(store: favorites) { url in
                web.open(url)
            }
        }
        .fullScreenCover(item: $player) { item in
            PlayerView(item: item)
        }
        .confirmationDialog(
            "Törlöd a böngészési adatokat, és kijelentkezel?",
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button("Törlés", role: .destructive) {
                web.clearAllData()
            }
            Button("Mégse", role: .cancel) {}
        }
        .onAppear {
            PrivacyScreen.shared.start()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                PrivacyScreen.shared.setInactive(false)
            case .inactive:
                PrivacyScreen.shared.setInactive(true)
            case .background:
                PrivacyScreen.shared.setInactive(true)
                if AppLock.isEnabled {
                    closeAllModals()
                }
            @unknown default:
                break
            }
        }
        .onChange(of: web.incognito) { _ in
            web.loadFailed = false
            web.progress = 0
        }
        .onChange(of: web.adBlockEnabled) { _ in
            web.applyAdBlock()
        }
        .onChange(of: network.isOnline) { online in
            if online && web.loadFailed {
                web.reload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            if shakePanic && !isPanic && !appLock.isLocked {
                panic()
            }
        }
    }

    // MARK: - Részek

    private var mainColumn: some View {
        VStack(spacing: 0) {
            webArea

            BottomBar(
                web: web,
                downloads: downloads,
                shakePanic: $shakePanic,
                onShare: shareCurrentPage,
                onAddFavorite: addFavorite,
                onShowFavorites: { showFavorites = true },
                onVideos: scanVideos,
                onShowDownloads: { showDownloads = true },
                onPanic: panic,
                onClear: { confirmClear = true }
            )
            .sheet(isPresented: $showDownloads) {
                DownloadsView(
                    manager: downloads,
                    onPlay: { url, title in
                        play(url, title: title)
                    },
                    onRetry: { item in
                        retryDownload(item)
                    }
                )
            }
        }
        .sheet(isPresented: $showVideos) {
            VideoLinksView(
                links: videoLinks,
                auth: authContext,
                onPlay: { url in
                    play(url, title: DownloadManager.displayName(for: url))
                },
                onDownload: { url in
                    startDownload(url)
                },
                onOpenPage: { url in
                    web.open(url)
                }
            )
        }
    }

    private var webArea: some View {
        ZStack(alignment: .top) {
            if web.blockerReady {
                WebView(state: web)
                    .id(web.incognito) // inkognitó váltáskor új, tiszta webnézet
            }

            if web.progress < 1 && !web.loadFailed {
                ProgressView(value: web.progress)
                    .progressViewStyle(.linear)
                    .allowsHitTesting(false)
            }

            if web.loadFailed {
                OfflineView(isOnline: network.isOnline) {
                    web.reload()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if web.incognito {
                IncognitoBadge()
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            toastView
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Gold.main, in: Capsule())
                .padding(.bottom, 12)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Műveletek

    private func shareCurrentPage() {
        guard let url = web.currentURL else { return }
        UIHelper.presentShareSheet(items: [url])
    }

    private func addFavorite() {
        guard let url = web.currentURL else { return }
        let title = web.pageTitle.isEmpty ? (url.host ?? "Oldal") : web.pageTitle
        favorites.add(title: title, url: url)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showToast("Kedvencekhez adva")
    }

    private func scanVideos() {
        web.findVideoLinks { links in
            web.authContext { auth in
                videoLinks = links
                authContext = auth
                showVideos = true
            }
        }
    }

    private func startDownload(_ url: URL) {
        let started = downloads.start(url: url, headers: authContext.headers(for: url))
        UINotificationFeedbackGenerator().notificationOccurred(started ? .success : .warning)
        showToast(started ? "Letöltés elindult" : "Ez már a letöltések között van")
    }

    private func retryDownload(_ item: DownloadItem) {
        guard let url = URL(string: item.url) else { return }
        web.authContext { auth in
            downloads.retry(item, headers: auth.headers(for: url))
        }
    }

    private func play(_ url: URL, title: String) {
        showVideos = false
        showDownloads = false
        let headers = url.isFileURL ? [:] : authContext.headers(for: url)
        // Megvárjuk, amíg a felugró lista becsukódik
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            player = PlayerItem(url: url, headers: headers, title: title)
        }
    }

    /// Vészkijelző: leállít minden médiát, bezár mindent, és a jegyzetek képernyőt mutatja.
    private func panic() {
        web.pauseAllMedia()
        closeAllModals()
        isPanic = true
    }

    private func closeAllModals() {
        showVideos = false
        showDownloads = false
        showFavorites = false
        player = nil
        UIHelper.dismissPresented()
    }

    private func showToast(_ text: String) {
        withAnimation {
            toast = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                toast = nil
            }
        }
    }
}

struct BottomBar: View {
    @ObservedObject var web: WebState
    @ObservedObject var downloads: DownloadManager
    @Binding var shakePanic: Bool
    let onShare: () -> Void
    let onAddFavorite: () -> Void
    let onShowFavorites: () -> Void
    let onVideos: () -> Void
    let onShowDownloads: () -> Void
    let onPanic: () -> Void
    let onClear: () -> Void

    private var activeDownloads: Int {
        downloads.items.filter { $0.status == .downloading }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            barButton("chevron.left", disabled: !web.canGoBack) {
                web.webView?.goBack()
            }
            barButton("chevron.right", disabled: !web.canGoForward) {
                web.webView?.goForward()
            }
            barButton("house") {
                web.goHome()
            }
            barButton("film", action: onVideos)
            downloadsButton
            barButton("hand.raised.fill", action: onPanic)
            moreMenu
        }
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private var downloadsButton: some View {
        Button(action: onShowDownloads) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 19))
                .frame(maxWidth: .infinity, minHeight: 44)
                .overlay(alignment: .topTrailing) {
                    if activeDownloads > 0 {
                        Text("\(activeDownloads)")
                            .font(.caption2.bold())
                            .foregroundColor(.black)
                            .padding(4)
                            .background(Gold.main, in: Circle())
                            .offset(x: -6, y: 2)
                    }
                }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                web.showFind()
            } label: {
                Label("Keresés az oldalon", systemImage: "magnifyingglass")
            }
            Button {
                web.reload()
            } label: {
                Label("Frissítés", systemImage: "arrow.clockwise")
            }
            Button(action: onShare) {
                Label("Oldal megosztása", systemImage: "square.and.arrow.up")
            }
            .disabled(web.currentURL == nil)

            Divider()

            Toggle(isOn: $web.incognito) {
                Label("Inkognitó mód", systemImage: "eye.slash")
            }
            Toggle(isOn: $web.adBlockEnabled) {
                Label("Reklámblokkoló", systemImage: "shield.lefthalf.filled")
            }
            Toggle(isOn: $web.landscapeVideo) {
                Label("Videó fekvő nézetben", systemImage: "rotate.right")
            }
            Toggle(isOn: $shakePanic) {
                Label("Rázás = vészkijelző", systemImage: "iphone.radiowaves.left.and.right")
            }

            Divider()

            Button(action: onAddFavorite) {
                Label("Oldal mentése kedvencnek", systemImage: "star")
            }
            Button(action: onShowFavorites) {
                Label("Kedvencek", systemImage: "list.star")
            }

            Menu {
                Button("Arany G (eredeti)") {
                    AppIcon.set(nil)
                }
                Button("Semleges (jegyzet)") {
                    AppIcon.set("NeutralIcon")
                }
            } label: {
                Label("Alkalmazás ikon", systemImage: "app")
            }

            Divider()

            Button(role: .destructive, action: onClear) {
                Label("Adatok törlése", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 19))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func barButton(_ icon: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(disabled)
    }
}
