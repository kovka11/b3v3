import LocalAuthentication
import SwiftUI

/// Face ID / Touch ID / kód zár. Háttérbe küldés után az app újra zárolódik.
final class AppLock: ObservableObject {
    /// Ha nem kell zár, állítsd false-ra.
    static let isEnabled = true

    @Published var isLocked = AppLock.isEnabled
    private var isAuthenticating = false

    func lock() {
        guard AppLock.isEnabled else { return }
        isLocked = true
    }

    func unlock() {
        guard AppLock.isEnabled, isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        authenticate(reason: "Feloldás a GoldenGate használatához") { [weak self] success in
            self?.isAuthenticating = false
            if success {
                self?.isLocked = false
            }
        }
    }

    /// Azonosítás Face ID-val vagy kóddal. Ha nincs beállítva kód a telefonon, nem zárja ki a felhasználót.
    func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
