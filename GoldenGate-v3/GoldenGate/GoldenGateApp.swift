import SwiftUI

@main
struct GoldenGateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appLock = AppLock()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appLock)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                appLock.lock()
            case .active:
                appLock.unlock()
            default:
                break
            }
        }
    }
}

/// A háttérben futó letöltések újraindulásához kell.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        DownloadManager.backgroundCompletionHandler = completionHandler
        _ = DownloadManager.shared
    }
}
