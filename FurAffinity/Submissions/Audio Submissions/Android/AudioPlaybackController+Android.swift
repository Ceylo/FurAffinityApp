//
//  AudioPlaybackController+Android.swift
//  FurAffinityUI (Android)
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is
//  `canImport(Android)`-guarded and no-ops on Darwin.
//

import SwiftUI
import FAKit
import Kingfisher
#if canImport(Android)
import SkipBridge
#endif

@MainActor
@Observable
final class AudioPlaybackController {
    private let streamUrl: URL
    private let title: String
    private let author: String
    private let coverImageUrl: URL
    private let downloadUrl: URL
    private let errorStorage: ErrorStorage
    private let fileUrl: URL
    private nonisolated let bridge = AudioBridge()

    private(set) var documentFileUrl: URL?

    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored private var isDownloading = false
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var seekToken = 0
    @ObservationIgnored private nonisolated(unsafe) var pollTask: Task<Void, Never>?

    init(
        streamUrl: URL,
        title: String,
        author: String,
        coverImageUrl: URL,
        downloadUrl: URL,
        downloadDocument _: @escaping (_ url: URL) async throws -> Data,
        errorStorage: ErrorStorage
    ) {
        self.streamUrl = streamUrl
        self.title = title
        self.author = author
        self.coverImageUrl = coverImageUrl
        self.downloadUrl = downloadUrl
        self.errorStorage = errorStorage
        fileUrl = FileManager.default.temporaryDirectory
            .appendingPathComponent(downloadUrl.lastPathComponent)
    }

    deinit {
        tearDown()
    }

    nonisolated func tearDown() {
        pollTask?.cancel()
        bridge.cancelDownload()
        bridge.release()
    }

    func prepare() async {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self?.poll() != nil else { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        var artworkPath = ""
        do {
            artworkPath = try await KingfisherManager.shared
                .retrieveFAImageFile(with: coverImageUrl).path
        } catch {
            logger.error("Now Playing artwork load failed for \(self.coverImageUrl): \(error)")
        }
        bridge.prepare(url: streamUrl, title: title, artist: author, artworkPath: artworkPath)
    }

    func startFileDownload() {
        guard documentFileUrl == nil, !isDownloading else { return }
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            documentFileUrl = fileUrl
            return
        }
        isDownloading = true
        let downloadUrl = downloadUrl
        let fileUrl = fileUrl
        Task { [weak self, bridge] in
            let result = await bridge.download(downloadUrl, to: fileUrl)
            guard let self else { return }
            self.isDownloading = false
            if result.ok == true {
                self.documentFileUrl = fileUrl
            } else if let message = result.error {
                self.store(message, action: "Audio Download", url: downloadUrl)
            }
        }
    }

    func play() {
        isPlaying = true
        bridge.play()
    }

    func pause() {
        isPlaying = false
        bridge.pause()
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        isSeeking = true
        seekToken += 1
        let token = seekToken
        bridge.seek(toMs: Int64(seconds * 1000))
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, token == self.seekToken else { return }
            self.isSeeking = false
        }
    }

    #if canImport(Android)
    func playButtonComposer() -> AnyDynamicObject {
        bridge.playButton(isPlaying: isPlaying)
    }
    #endif

    private func poll() {
        guard let snapshot = bridge.snapshot() else { return }
        if isPlaying != snapshot.isPlaying {
            isPlaying = snapshot.isPlaying
        }
        let position = Double(snapshot.positionMs) / 1000
        if !isSeeking, currentTime != position {
            currentTime = position
        }
        let total = Double(snapshot.durationMs) / 1000
        if snapshot.durationMs >= 0, duration != total {
            duration = total
        }
        if let message = snapshot.error {
            store(message, action: "Audio Playback", url: streamUrl)
        }
    }

    private func store(_ message: String, action: String, url: URL) {
        storeError(
            RichLocalizedError(relatedAction: action, webBrowserURL: url, errorDescription: message),
            in: errorStorage,
            action: action,
            webBrowserURL: url
        )
    }
}

#if DEBUG
extension AudioPlaybackController {
    static func preview(currentTime: Double = 0, duration: Double = 100) -> AudioPlaybackController {
        let controller = AudioPlaybackController(
            streamUrl: URL(string: "https://example.invalid/preview.mp3")!,
            title: "Some title",
            author: "author",
            coverImageUrl: URL(string: "https://example.invalid/preview.jpg")!,
            downloadUrl: URL(string: "https://example.invalid/preview.mp3")!,
            downloadDocument: { _ in Data() },
            errorStorage: ErrorStorage()
        )
        controller.currentTime = currentTime
        controller.duration = duration
        return controller
    }
}
#endif

private final class AudioBridge: @unchecked Sendable {
    struct Snapshot: Decodable {
        var isPlaying: Bool
        var positionMs: Int64
        var durationMs: Int64
        var error: String?
    }

    struct DownloadResult: Decodable {
        var ok: Bool?
        var error: String?
    }

    #if canImport(Android)
    private let object: AnyDynamicObject

    init() {
        object = try! AnyDynamicObject(className: "fur.affinity.ui.FAAudioBridge")
    }
    #else
    init() {}
    #endif

    func prepare(url: URL, title: String, artist: String, artworkPath: String) {
        #if canImport(Android)
        let _: Bool? = try? object.prepare(url.absoluteString, title, artist, artworkPath)
        #endif
    }

    func play() {
        #if canImport(Android)
        let _: Bool? = try? object.play()
        #endif
    }

    func pause() {
        #if canImport(Android)
        let _: Bool? = try? object.pause()
        #endif
    }

    #if canImport(Android)
    func playButton(isPlaying: Bool) -> AnyDynamicObject {
        let button: AnyDynamicObject? = try! object.playButton(isPlaying)
        return button!
    }
    #endif

    func seek(toMs ms: Int64) {
        #if canImport(Android)
        let _: Bool? = try? object.seekTo(ms)
        #endif
    }

    func release() {
        #if canImport(Android)
        let _: Bool? = try? object.release()
        #endif
    }

    func cancelDownload() {
        #if canImport(Android)
        let _: Bool? = try? object.cancelDownload()
        #endif
    }

    func snapshot() -> Snapshot? {
        #if canImport(Android)
        let json: String? = try? object.snapshot()
        return decode(json)
        #else
        return nil
        #endif
    }

    func download(_ url: URL, to fileUrl: URL) async -> DownloadResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                #if canImport(Android)
                let json: String? = try? self.object.download(url.absoluteString, fileUrl.path)
                let result = self.decode(json) ?? DownloadResult(error: "no download result")
                #else
                let result = DownloadResult()
                #endif
                continuation.resume(returning: result)
            }
        }
    }

    private func decode<T: Decodable>(_ json: String?) -> T? {
        guard let data = json?.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("AudioBridge: unreadable result \(json ?? ""): \(error)")
            return nil
        }
    }
}
