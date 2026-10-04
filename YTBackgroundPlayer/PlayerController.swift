import AVFoundation
import Combine
import MediaPlayer
import UIKit
import WebKit

/// Owns the YouTube web view and bridges it to iOS audio / lock-screen APIs.
@MainActor
final class PlayerController: NSObject, ObservableObject {
    static let homeURL = URL(string: "https://m.youtube.com")!

    let webView: WKWebView

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isPlaying = false
    @Published private(set) var nowPlayingTitle: String?

    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var artworkURL: String?
    private var artwork: MPMediaItemArtwork?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        // Look like mobile Safari so YouTube serves its normal mobile site.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: BackgroundScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        contentController.add(WeakScriptMessageHandler(self), name: BackgroundScript.messageName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
        ]

        configureAudioSession()
        configureRemoteCommands()
        observeLifecycle()

        webView.load(URLRequest(url: Self.homeURL))
    }

    // MARK: - Navigation

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func goHome() { webView.load(URLRequest(url: Self.homeURL)) }
    func reload() { webView.reload() }

    // MARK: - Playback commands

    func play() { runJS("window.__bgPlay && __bgPlay.play()") }
    func pause() { runJS("window.__bgPlay && __bgPlay.pause()") }
    func togglePlayPause() { runJS("window.__bgPlay && __bgPlay.toggle()") }
    func next() { runJS("window.__bgPlay && __bgPlay.next()") }
    func previous() { runJS("window.__bgPlay && __bgPlay.previous()") }
    func seek(to seconds: Double) { runJS("window.__bgPlay && __bgPlay.seek(\(seconds))") }

    private func runJS(_ script: String) {
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - Audio session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("AVAudioSession error: \(error)")
        }
    }

    // MARK: - Lifecycle

    private func observeLifecycle() {
        let center = NotificationCenter.default

        notificationTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.enterBackground() }
        })

        notificationTokens.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.runJS("window.__bgPlay && __bgPlay.setBackground(false)") }
        })

        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo
            MainActor.assumeIsolated { self?.handleInterruption(info) }
        })
    }

    private func enterBackground() {
        configureAudioSession()
        runJS("window.__bgPlay && __bgPlay.setBackground(true)")
        // WebKit sometimes pauses media a moment after backgrounding; nudge it again.
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    self?.runJS("window.__bgPlay && __bgPlay.resumeIfNeeded()")
                }
            }
        }
    }

    private func handleInterruption(_ info: [AnyHashable: Any]?) {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // Treat calls / Siri as a user pause so we don't fight the system.
            if isPlaying { pause() }
        case .ended:
            let optionsRaw = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                configureAudioSession()
                play()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Lock screen / Control Center

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            MainActor.assumeIsolated { self?.seek(to: position) }
            return .success
        }
    }

    fileprivate func handleState(_ body: [String: Any]) {
        let hasVideo = body["hasVideo"] as? Bool ?? false
        let playing = body["playing"] as? Bool ?? false
        let title = (body["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        if isPlaying != playing { isPlaying = playing }
        let shownTitle = hasVideo ? title : nil
        if nowPlayingTitle != shownTitle { nowPlayingTitle = shownTitle }

        guard hasVideo else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title ?? "YouTube",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: body["currentTime"] as? Double ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? (body["rate"] as? Double ?? 1) : 0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist = body["artist"] as? String, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let duration = body["duration"] as? Double, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let urlString = body["artwork"] as? String, !urlString.isEmpty, urlString != artworkURL {
            loadArtwork(urlString)
        }
    }

    private func loadArtwork(_ urlString: String) {
        artworkURL = urlString
        artwork = nil
        guard let url = URL(string: urlString) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.artworkURL == urlString else { return }
                    self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                }
            }
        }.resume()
    }
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension PlayerController: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        // Block "open in YouTube app" style links (youtube://, intent://, ...).
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        let allowed: Set<String> = ["http", "https", "about", "blob", "data"]
        return allowed.contains(scheme) ? .allow : .cancel
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" links open in the same view.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - Script message bridge

/// Avoids the retain cycle WKUserContentController creates with its handlers.
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: PlayerController?

    init(_ target: PlayerController) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        target?.handleState(body)
    }
}
