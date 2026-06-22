//
//  AudioPlaybackController.swift
//  FurAffinity
//
//  Created by Ceylo on 22/06/2026.
//

import SwiftUI
import AVFoundation
import MediaPlayer
import Kingfisher
import FAKit
import os

/// Owns the `AVPlayer` and every playback side-effect for an audio submission so
/// `SubmissionAudioContent` can stay a thin shell: the authenticated asset, the
/// audio session (play over the silent switch + background), Now Playing info for
/// the lock screen, remote transport commands, interruption handling, and error
/// surfacing. Playback lives for the controller's lifetime; teardown happens on
/// `deinit`.
@MainActor
@Observable
final class AudioPlaybackController {
    private let streamUrl: URL
    private let title: String
    private let author: String
    private let coverImageUrl: URL
    private let errorStorage: ErrorStorage

    private(set) var player: AVPlayer?

    /// Observable playback state driving the SwiftUI transport controls.
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var interruptionObserver: NSObjectProtocol?
    private var audioSessionConfigured = false
    private var audioSessionActivated = false

    /// Captured at setup so `deinit` (nonisolated) can release resources without
    /// touching main-actor-isolated state.
    @ObservationIgnored
    private nonisolated(unsafe) var teardown: (() -> Void)?

    init(
        streamUrl: URL,
        title: String,
        author: String,
        coverImageUrl: URL,
        errorStorage: ErrorStorage
    ) {
        self.streamUrl = streamUrl
        self.title = title
        self.author = author
        self.coverImageUrl = coverImageUrl
        self.errorStorage = errorStorage
    }

    deinit {
        teardown?()
    }

    /// Builds the authenticated player and wires observers, Now Playing, and
    /// remote commands. Safe to call once from a `.task`.
    func prepare() async {
        guard player == nil else { return }

        let userAgent = await FAUserAgent.current()
        let asset = AVURLAsset(url: streamUrl, options: [
            AVURLAssetHTTPCookiesKey: HTTPCookieStorage.shared.cookies ?? [],
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": userAgent],
        ])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // Set the category up front (without activating, so other apps' audio
        // isn't interrupted on appear); activation is deferred to first play.
        configureAudioSessionCategory()
        observeStatus(of: item)
        observeTimeControlStatus(of: player)
        addPeriodicTimeObserver(to: player)
        configureRemoteCommands(for: player)
        observeInterruptions()
        updateNowPlayingStaticInfo()
        await loadArtwork()

        let commandCenter = MPRemoteCommandCenter.shared()
        let token = timeObserverToken
        let observer = interruptionObserver
        teardown = {
            if let token { player.removeTimeObserver(token) }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            commandCenter.playCommand.removeTarget(nil)
            commandCenter.pauseCommand.removeTarget(nil)
            commandCenter.togglePlayPauseCommand.removeTarget(nil)
            commandCenter.changePlaybackPositionCommand.removeTarget(nil)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// Starts playback. Also drives remote-command play. The audio session is
    /// activated lazily once the player actually starts (see the
    /// `timeControlStatus` observer), so this works whether play is triggered
    /// here or by the native transport controls.
    func play() {
        player?.play()
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    func pause() {
        player?.pause()
        MPNowPlayingInfoCenter.default().playbackState = .paused
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = seconds
        updateNowPlayingPlaybackState()
    }

    // MARK: - Audio session

    /// Sets the `.playback` category (over the ring/silent switch, survives
    /// backgrounding) without activating, so other apps keep playing until the
    /// user actually starts this audio.
    private func configureAudioSessionCategory() {
        guard !audioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            audioSessionConfigured = true
        } catch {
            logger.error("Audio session category setup failed: \(error)")
        }
    }

    private func activateAudioSessionIfNeeded() {
        guard !audioSessionActivated else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            audioSessionActivated = true
        } catch {
            logger.error("Audio session activation failed: \(error)")
        }
    }

    // MARK: - Observers

    private func observeTimeControlStatus(of player: AVPlayer) {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = isPlaying
                if isPlaying { self.activateAudioSessionIfNeeded() }
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            Task { @MainActor [weak self] in
                self?.surfaceFailure(error)
            }
        }
    }

    private func surfaceFailure(_ error: (any Error)?) {
        let underlying = error ?? AudioPlaybackError.playbackFailed
        storeError(
            underlying,
            in: errorStorage,
            action: "Audio Playback",
            webBrowserURL: streamUrl
        )
    }

    private func addPeriodicTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite {
                    self.duration = itemDuration
                }
                self.updateNowPlayingPlaybackState()
            }
        }
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable primitives before crossing into the main actor.
            let info = notification.userInfo
            let rawType = info?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt) {
        guard
            let rawType,
            let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume) {
                play()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Remote commands

    private func configureRemoteCommands(for player: AVPlayer) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let player = self.player else { return .commandFailed }
            if player.timeControlStatus == .paused {
                self.play()
            } else {
                self.pause()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard
                let self,
                let player = self.player,
                let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            let time = CMTime(seconds: event.positionTime, preferredTimescale: 600)
            player.seek(to: time)
            self.updateNowPlayingPlaybackState()
            return .success
        }
    }

    // MARK: - Now Playing

    private func updateNowPlayingStaticInfo() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyArtist] = author
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateNowPlayingPlaybackState() {
        guard let player, let item = player.currentItem else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        let duration = item.duration.seconds
        if duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork() async {
        do {
            let result = try await KingfisherManager.shared.retrieveImage(
                with: coverImageUrl,
                options: [.requestModifier(FAUserAgentRequestModifier())]
            )
            let artwork = Self.makeArtwork(from: result.image)
            var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
            info[MPMediaItemPropertyArtwork] = artwork
            MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        } catch {
            logger.error("Now Playing artwork load failed for \(self.coverImageUrl): \(error)")
        }
    }

    /// Builds the artwork in a nonisolated context so its request handler — which
    /// MediaPlayer invokes on its own background queue — doesn't inherit main-actor
    /// isolation (that would trip Swift's executor check and crash).
    private nonisolated static func makeArtwork(from image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

private enum AudioPlaybackError: LocalizedError {
    case playbackFailed

    var errorDescription: String? {
        "The audio could not be played."
    }
}
