import AppKit
import Combine
import MultipeerConnectivity

enum MarkerSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .small: "Маленькие"
        case .medium: "Средние"
        case .large: "Большие"
        }
    }
    var points: CGFloat {
        switch self {
        case .small: 110
        case .medium: 150
        case .large: 200
        }
    }
}

@MainActor
final class MacModel: ObservableObject {
    @Published private(set) var peerNames: [String] = []
    @Published private(set) var lastEvent = "Жду iPhone…"
    @Published private(set) var isOverlayVisible = false
    @Published var markerSize: MarkerSize = .medium {
        didSet { overlay.state.markerSize = markerSize.points }
    }

    private let link = PeerLink(displayName: Host.current().localizedName ?? "Mac", role: .advertiser)
    private let overlay = MarkerOverlay()
    private let picker = ScreenPicker()
    private var cancellables = Set<AnyCancellable>()

    init() {
        overlay.state.markerSize = markerSize.points
        link.$connectedPeers
            .sink { [weak self] peers in self?.peerNames = peers.map(\.displayName) }
            .store(in: &cancellables)
        link.onMessage = { [weak self] message, peer in self?.handle(message, from: peer) }
        link.start()
    }

    func toggleOverlay() {
        isOverlayVisible ? hideOverlay() : showOverlay()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func handle(_ message: DracaMessage, from peer: MCPeerID) {
        switch message {
        case .aimStart:
            showOverlay()
        case let .aim(x, y):
            overlay.state.reticle = CGPoint(x: x, y: y)
        case .aimLost:
            overlay.state.reticle = nil
        case .aimCancel:
            hideOverlay()
        case let .pick(x, y):
            hideOverlay()
            Task { await pick(at: CGPoint(x: x, y: y), for: peer) }
        case .link, .pickFailed:
            break
        }
    }

    private func pick(at point: CGPoint, for peer: MCPeerID) async {
        // Даём оверлею исчезнуть, чтобы он не попал в hit-test и снимок.
        try? await Task.sleep(for: .milliseconds(80))
        do {
            switch try await picker.pick(atNormalized: point) {
            case let .file(url):
                lastEvent = "Отправляю \(url.lastPathComponent)…"
                link.sendFile(url, to: peer) { [weak self] error in
                    self?.lastEvent = error == nil ? "Отправлено: \(url.lastPathComponent)" : "Ошибка: \(error!.localizedDescription)"
                }
            case let .link(url):
                link.send(.link(url: url.absoluteString), to: [peer])
                lastEvent = "Ссылка: \(url.absoluteString)"
            }
        } catch {
            link.send(.pickFailed(reason: error.localizedDescription), to: [peer])
            lastEvent = "Не вышло: \(error.localizedDescription)"
        }
    }

    private func showOverlay() {
        overlay.show()
        isOverlayVisible = true
    }

    private func hideOverlay() {
        overlay.hide()
        isOverlayVisible = false
    }
}
