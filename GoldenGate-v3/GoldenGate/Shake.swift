import UIKit

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("goldengate.deviceDidShake")
}

extension UIWindow {
    /// Telefonrázás figyelése az egész appban (vészkijelző).
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
