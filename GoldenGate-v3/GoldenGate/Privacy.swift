import UIKit

/// Fekete takaró, ami MINDEN fölé kerül (a felugró ablakok fölé is):
/// az alkalmazásváltóban és képernyőfelvétel közben ez látszik az oldal helyett.
final class PrivacyScreen {
    static let shared = PrivacyScreen()

    private var shield: UIView?
    private var messageLabel: UILabel?
    private var isInactive = false
    private var isCaptured = false
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        isCaptured = UIScreen.main.isCaptured
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isCaptured = UIScreen.main.isCaptured
            self?.refresh()
        }
        refresh()
    }

    func setInactive(_ value: Bool) {
        isInactive = value
        refresh()
    }

    private func refresh() {
        if isInactive || isCaptured {
            show()
        } else {
            hide()
        }
    }

    private func show() {
        if shield == nil {
            guard let window = PrivacyScreen.keyWindow() else { return }

            let view = UIView(frame: window.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = .black

            let logo = UILabel()
            logo.text = "G"
            logo.font = UIFont.systemFont(ofSize: 72, weight: .bold)
            logo.textColor = UIColor(red: 0.94, green: 0.82, blue: 0.43, alpha: 1)

            let message = UILabel()
            message.font = UIFont.systemFont(ofSize: 13)
            message.textColor = UIColor(white: 1, alpha: 0.7)
            message.textAlignment = .center
            message.numberOfLines = 0

            let stack = UIStackView(arrangedSubviews: [logo, message])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
            ])

            window.addSubview(view)
            shield = view
            messageLabel = message
        }
        messageLabel?.text = isCaptured ? "Képernyőfelvétel közben a tartalom el van rejtve." : nil
        if let shield {
            shield.superview?.bringSubviewToFront(shield)
        }
    }

    private func hide() {
        shield?.removeFromSuperview()
        shield = nil
        messageLabel = nil
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
