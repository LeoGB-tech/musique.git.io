import AVFoundation
import MediaPlayer
import UIKit

@MainActor
final class PlayerController: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0

    private var queue: [Track] = []
    private var index = 0
    private let player = AVPlayer()
    private var artwork: MPMediaItemArtwork?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
            }
        }
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }

        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.resume() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent {
                let p = e.positionTime
                Task { @MainActor in self?.seek(to: p) }
            }
            return .success
        }
    }

    func play(_ track: Track, in list: [Track]) {
        queue = list
        index = list.firstIndex(of: track) ?? 0
        start(queue[index])
    }

    func shuffle(_ list: [Track]) {
        guard !list.isEmpty else { return }
        queue = list.shuffled()
        index = 0
        start(queue[0])
    }

    private func start(_ t: Track) {
        guard t.downloaded else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: t.url)
            return
        }
        current = t
        let item = AVPlayerItem(url: t.url)
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
        position = 0
        duration = 0
        artwork = nil
        updateNowPlaying()
        Task {
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
                duration = d.seconds
                updateNowPlaying()
            }
        }
        Task {
            if let img = await ArtworkLoader.shared.image(for: t), current?.id == t.id {
                artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                updateNowPlaying()
            }
        }
    }

    func resume() { player.play(); isPlaying = true; updateNowPlaying() }
    func pause() { player.pause(); isPlaying = false; updateNowPlaying() }
    func toggle() { isPlaying ? pause() : resume() }

    func next() {
        if index + 1 < queue.count {
            index += 1
            start(queue[index])
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        if position > 3 || index == 0 {
            seek(to: 0)
        } else {
            index -= 1
            start(queue[index])
        }
    }

    func seek(to seconds: Double) {
        position = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let t = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
