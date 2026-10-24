import SwiftUI
import WebKit

/// A webnézet és a SwiftUI közötti állapot.
final class WebState: ObservableObject {
    @Published var loadFailed = false
    @Published var progress: Double = 0
    @Published var themeColor: Color?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var pageTitle = ""
    @Published var blockerReady = false
    @Published var userAgent = ""

    /// Inkognitó: nem tárol sütit és belépést. Indításkor mindig ki van kapcsolva.
    @Published var incognito = false

    @Published var adBlockEnabled: Bool {
        didSet { UserDefaults.standard.set(adBlockEnabled, forKey: "goldengate.adBlock") }
    }
    @Published var landscapeVideo: Bool {
        didSet { UserDefaults.standard.set(landscapeVideo, forKey: "goldengate.landscapeVideo") }
    }

    weak var webView: WKWebView?
    private(set) var ruleList: WKContentRuleList?

    init() {
        let defaults = UserDefaults.standard
        adBlockEnabled = defaults.object(forKey: "goldengate.adBlock") as? Bool ?? true
        landscapeVideo = defaults.object(forKey: "goldengate.landscapeVideo") as? Bool ?? true
        compileBlocker()
    }

    private func compileBlocker() {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "goldengate-adblock-v1",
            encodedContentRuleList: AdBlockRules.json
        ) { [weak self] list, _ in
            DispatchQueue.main.async {
                self?.ruleList = list
                self?.blockerReady = true
            }
        }
    }

    func applyAdBlock() {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if adBlockEnabled, let ruleList {
            controller.add(ruleList)
        }
        webView.reload()
    }

    func reload() {
        loadFailed = false
        guard let webView else { return }
        if webView.url == nil {
            webView.load(URLRequest(url: startURL))
        } else {
            webView.reload()
        }
    }

    /// Süti- és fejlécadatok a letöltésekhez és a lejátszáshoz (a belépett munkameneted alapján).
    func authContext(completion: @escaping (AuthContext) -> Void) {
        let agent = userAgent
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else {
            completion(AuthContext(cookies: [], userAgent: agent))
            return
        }
        store.getAllCookies { cookies in
            DispatchQueue.main.async {
                completion(AuthContext(cookies: cookies, userAgent: agent))
            }
        }
    }

    /// Minden hang és videó leállítása, teljes képernyő bezárása.
    func pauseAllMedia() {
        webView?.pauseAllMediaPlayback(completionHandler: nil)
        webView?.evaluateJavaScript(
            "if (document.webkitFullscreenElement) { document.webkitExitFullscreen(); }",
            completionHandler: nil
        )
    }

    /// Az iOS beépített keresősávja az oldalon belül.
    func showFind() {
        webView?.isFindInteractionEnabled = true
        webView?.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    func goHome() {
        loadFailed = false
        webView?.load(URLRequest(url: startURL))
    }

    func open(_ url: URL) {
        loadFailed = false
        webView?.load(URLRequest(url: url))
    }

    /// Az aktuális oldal összes .mp4 és .avi linkje (a kódban, scriptekben és a lejátszókban is keres).
    func findVideoLinks(completion: @escaping ([URL]) -> Void) {
        let js = #"""
        (function () {
          var found = {};
          var ext = /\.(mp4|avi)(\?|#|$)/i;
          function add(u) {
            if (!u) { return; }
            try {
              var abs = new URL(u, document.baseURI).href;
              if (ext.test(abs)) { found[abs] = true; }
            } catch (e) {}
          }
          var attrs = ['href', 'src', 'data-src', 'data-video', 'data-href', 'data-url'];
          document.querySelectorAll('a[href], video, source, [data-src], [data-video], [data-href], [data-url]').forEach(function (el) {
            attrs.forEach(function (a) { add(el.getAttribute(a)); });
            if (el.currentSrc) { add(el.currentSrc); }
          });
          var html = document.documentElement.innerHTML.replace(/\\\//g, '/');
          var re = /https?:\/\/[^"'\s<>\\)]+?\.(?:mp4|avi)(?:\?[^"'\s<>\\)]*)?/gi;
          var m;
          while ((m = re.exec(html)) !== null) { add(m[0]); }
          return Object.keys(found);
        })();
        """#

        guard let webView else {
            completion([])
            return
        }
        webView.evaluateJavaScript(js) { result, _ in
            let strings = (result as? [String]) ?? []
            let urls = strings.compactMap { URL(string: $0) }
            DispatchQueue.main.async {
                completion(urls)
            }
        }
    }

    /// Süti, belépés, gyorsítótár törlése, majd vissza a kezdőoldalra.
    func clearAllData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.goHome()
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let state: WebState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = state.incognito ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore.default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = true

        if state.adBlockEnabled, let list = state.ruleList {
            config.userContentController.add(list)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        webView.isFindInteractionEnabled = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .clear

        // Húzd le a frissítéshez
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.handleRefresh(_:)),
                          for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        context.coordinator.attach(webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        private let state: WebState
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(state: WebState) {
            self.state = state
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            state.webView = webView

            observations = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.state.progress = view.estimatedProgress }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.state.canGoBack = view.canGoBack }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.state.canGoForward = view.canGoForward }
                },
                webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.state.currentURL = view.url }
                },
                webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.state.pageTitle = view.title ?? "" }
                },
                webView.observe(\.fullscreenState, options: [.new]) { [weak self] view, _ in
                    DispatchQueue.main.async { self?.handleFullscreen(view.fullscreenState) }
                }
            ]
        }

        @objc func handleRefresh(_ sender: UIRefreshControl) {
            state.reload()
        }

        // MARK: - Teljes képernyős videó: fekvő nézet

        private func handleFullscreen(_ fullscreen: WKWebView.FullscreenState) {
            guard state.landscapeVideo else { return }
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0 is UIWindowScene }) as? UIWindowScene else { return }

            switch fullscreen {
            case .enteringFullscreen:
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in }
            case .notInFullscreen:
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .allButUpsideDown)) { _ in }
            default:
                break
            }
        }

        // MARK: - Betöltés és hibák

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            state.loadFailed = false
            updateThemeColor(from: webView)
            webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, _ in
                if let agent = result as? String {
                    self?.state.userAgent = agent
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleFailure(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleFailure(error)
        }

        private func handleFailure(_ error: Error) {
            webView?.scrollView.refreshControl?.endRefreshing()
            let nsError = error as NSError
            // Megszakított betöltés (pl. új link vagy letöltés indult) nem hiba
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
            state.loadFailed = true
        }

        // MARK: - Színek

        private func updateThemeColor(from webView: WKWebView) {
            let js = """
            (function () {
              var m = document.querySelector('meta[name="theme-color"]');
              if (m && m.content) { return m.content; }
              var el = document.body || document.documentElement;
              return el ? getComputedStyle(el).backgroundColor : '';
            })();
            """
            webView.evaluateJavaScript(js) { [weak self, weak webView] result, _ in
                guard let self, let css = result as? String, let color = UIColor(css: css) else { return }
                self.state.themeColor = Color(color)
                webView?.underPageBackgroundColor = color
            }
        }

        // MARK: - Linkek

        // A goldengate.hu linkjei az appban nyílnak, a többi a Safariban.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }

            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = target.scheme?.lowercased() ?? ""
            let isInternal = Site.isInternal(target.host)

            if ["mailto", "tel", "sms"].contains(scheme) {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            } else if navigationAction.navigationType == .linkActivated && !isInternal {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Felugró ablakok blokkolása: csak a saját oldal linkjei nyílhatnak új ablakban,
        // és csak ha te kattintottál rá.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard
                navigationAction.targetFrame == nil,
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url
            else { return nil }

            if Site.isInternal(url.host) {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
            return nil
        }

        // MARK: - Fájlletöltés

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = navigationResponse.response as? HTTPURLResponse,
               let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
               disposition.lowercased().hasPrefix("attachment") {
                decisionHandler(.download)
                return
            }
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                completionHandler(nil)
                return
            }
            let destination = folder.appendingPathComponent(suggestedFilename)
            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        // Letöltés után megjelenik a megosztás menü (Mentés a Fájlokba, Fotók, AirDrop...)
        func downloadDidFinish(_ download: WKDownload) {
            guard let file = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
            UIHelper.presentShareSheet(items: [file])
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        }

        // MARK: - Kamera és mikrofon

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(Site.isInternal(origin.host) ? .grant : .deny)
        }

        // MARK: - JavaScript alert / confirm

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            UIHelper.presentAlert(message: message, withCancel: false) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            UIHelper.presentAlert(message: message, withCancel: true, completion: completionHandler)
        }
    }
}
