import AVFoundation
import AVKit
import SwiftUI

// MARK: - Lejátszási pozíció megjegyzése

final class PlaybackStore {
    static let shared = PlaybackStore()
    private static let storageKey = "goldengate.playback"

    private var cache: [String: Double]

    init() {
        cache = (UserDefaults.standard.dictionary(forKey: PlaybackStore.storageKey) as? [String: Double]) ?? [:]
    }

    func position(for key: String) -> Double? {
        cache[key]
    }

    func set(_ seconds: Double, for key: String) {
        cache[key] = seconds
        persist()
    }

    func clear(_ key: String) {
        cache[key] = nil
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(cache, forKey: PlaybackStore.storageKey)
    }
}

// MARK: - Lejátszó

struct PlayerItem: Identifiable {
    let id = UUID()
    let url: URL
    let headers: [String: String]
    let title: String
}

final class PlayerModel: ObservableObject {
    static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    let player: AVPlayer
    @Published var speed: Float = 1

    private let key: String
    private var timeObserver: Any?
    private var finished = false

    init(item: PlayerItem) {
        key = item.url.isFileURL ? item.url.lastPathComponent : item.url.absoluteString

        let asset: AVURLAsset
        if item.url.isFileURL {
            asset = AVURLAsset(url: item.url)
        } else {
            asset = AVURLAsset(url: item.url, options: ["AVURLAssetHTTPHeaderFieldsKey": item.headers])
        }
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        // Ott folytatja, ahol abbahagytad
        if let saved = PlaybackStore.shared.position(for: key), saved > 5 {
            player.seek(to: CMTime(seconds: saved, preferredTimescale: 600))
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { [weak self] _ in
            self?.savePosition()
        }

        player.play()
    }

    deinit {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
        }
    }

    func skip(_ seconds: Double) {
        let current = CMTimeGetSeconds(player.currentTime())
        guard current.isFinite else { return }
        player.seek(to: CMTime(seconds: max(0, current + seconds), preferredTimescale: 600))
    }

    func setSpeed(_ value: Float) {
        speed = value
        player.defaultRate = value
        if player.timeControlStatus != .paused {
            player.rate = value
        }
    }

    /// Bezáráskor: pozíció mentése, lejátszás leállítása.
    func finish() {
        guard !finished else { return }
        finished = true
        savePosition()
        player.pause()
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func savePosition() {
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite else { return }

        var duration = CMTimeGetSeconds(player.currentItem?.duration ?? CMTime.indefinite)
        if !duration.isFinite {
            duration = 0
        }

        if duration > 0 && seconds > duration - 10 {
            PlaybackStore.shared.clear(key) // végignézte
        } else {
            PlaybackStore.shared.set(seconds, for: key)
        }
    }
}

struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}

struct PlayerView: View {
    let item: PlayerItem
    @StateObject private var model: PlayerModel
    @Environment(\.dismiss) private var dismiss

    init(item: PlayerItem) {
        self.item = item
        _model = StateObject(wrappedValue: PlayerModel(item: item))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.finish()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Text(item.title)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                Color.clear.frame(width: 26, height: 26)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            PlayerControllerView(player: model.player)

            HStack(spacing: 28) {
                controlButton("gobackward.10") { model.skip(-10) }
                controlButton("goforward.10") { model.skip(10) }

                Menu {
                    ForEach(PlayerModel.speeds, id: \.self) { value in
                        Button {
                            model.setSpeed(value)
                        } label: {
                            if model.speed == value {
                                Label(speedLabel(value), systemImage: "checkmark")
                            } else {
                                Text(speedLabel(value))
                            }
                        }
                    }
                } label: {
                    Label(speedLabel(model.speed), systemImage: "speedometer")
                        .foregroundColor(.white)
                        .frame(minWidth: 90, minHeight: 44)
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear {
            model.finish()
        }
    }

    private func controlButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(.white)
                .frame(width: 52, height: 44)
        }
    }

    private func speedLabel(_ value: Float) -> String {
        String(format: "%gx", Double(value))
    }
}
