import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            WebViewContainer(webView: player.webView)
            Divider()
            controlBar
        }
        .background(Color(.systemBackground))
    }

    private var controlBar: some View {
        VStack(spacing: 6) {
            if let title = player.nowPlayingTitle {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                barButton("chevron.backward", enabled: player.canGoBack) { player.goBack() }
                barButton("chevron.forward", enabled: player.canGoForward) { player.goForward() }
                barButton("house") { player.goHome() }
                barButton("arrow.clockwise") { player.reload() }
                barButton(player.isPlaying ? "pause.fill" : "play.fill") { player.togglePlayPause() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func barButton(_ systemName: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .disabled(!enabled)
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
