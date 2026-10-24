import SwiftUI
import UIKit

enum Site {
    static let host = "goldengate.hu"

    static func isInternal(_ candidate: String?) -> Bool {
        guard let h = candidate?.lowercased() else { return false }
        return h == host || h.hasSuffix("." + host)
    }
}

enum UIHelper {
    static func topViewController() -> UIViewController? {
        guard
            let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    static func presentAlert(message: String, withCancel: Bool, completion: @escaping (Bool) -> Void) {
        guard let top = topViewController() else {
            completion(false)
            return
        }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        if withCancel {
            alert.addAction(UIAlertAction(title: "Mégse", style: .cancel) { _ in completion(false) })
        }
        top.present(alert, animated: true)
    }

    /// Minden felugró ablak (megosztás menü, teljes képernyős videó) azonnali bezárása.
    static func dismissPresented() {
        DispatchQueue.main.async {
            guard
                let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene,
                let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
            else { return }
            root.presentedViewController?.dismiss(animated: false)
        }
    }

    static func presentShareSheet(items: [Any]) {
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(sheet, animated: true)
        }
    }
}

/// Alkalmazás ikon váltása (a névről lásd a megjegyzést: az iOS csak az ikont engedi cserélni).
enum AppIcon {
    static func set(_ name: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(name) { _ in }
    }
}

extension UIColor {
    /// CSS színből (#rgb, #rrggbb, rgb(), rgba()) UIColor. Átlátszó szín esetén nil.
    convenience init?(css: String) {
        let s = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
            if hex.count == 3 || hex.count == 4 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }

            let r: CGFloat
            let g: CGFloat
            let b: CGFloat
            let a: CGFloat
            if hex.count == 6 {
                r = CGFloat((value >> 16) & 0xFF) / 255
                g = CGFloat((value >> 8) & 0xFF) / 255
                b = CGFloat(value & 0xFF) / 255
                a = 1
            } else {
                r = CGFloat((value >> 24) & 0xFF) / 255
                g = CGFloat((value >> 16) & 0xFF) / 255
                b = CGFloat((value >> 8) & 0xFF) / 255
                a = CGFloat(value & 0xFF) / 255
            }
            guard a > 0 else { return nil }
            self.init(red: r, green: g, blue: b, alpha: a)
            return
        }

        if s.hasPrefix("rgb") {
            let numbers = s
                .split(whereSeparator: { !"0123456789.".contains($0) })
                .compactMap { Double($0) }
            guard numbers.count >= 3 else { return nil }
            let alpha = numbers.count >= 4 ? min(numbers[3], 1) : 1
            guard alpha > 0 else { return nil }
            self.init(red: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: alpha)
            return
        }

        return nil
    }
}
