import Combine
import UIKit

struct ReceivedItem: Identifiable {
    enum Kind {
        case file(URL)
        case link(URL)
    }

    let id = UUID()
    let kind: Kind
}

@MainActor
final class PhoneModel: ObservableObject {
    enum AimState { case idle, searching, locked }

    @Published private(set) var macName: String?
    @Published private(set) var aimState: AimState = .idle
    @Published private(set) var visibleMarkers = 0
    @Published private(set) var statusMessage: String?
    @Published var received: ReceivedItem?

    let camera = CameraController()
    private let tracker = MarkerTracker()
    private let link = PeerLink(displayName: UIDevice.current.name, role: .browser)
    private var cancellables = Set<AnyCancellable>()

    private var isAiming = false
    private var lastPoint: CGPoint?
    private var lastPointDate = Date.distantPast
    private let haptics = UIImpactFeedbackGenerator(style: .medium)

    init() {
        link.$connectedPeers
            .sink { [weak self] peers in self?.macName = peers.first?.displayName }
            .store(in: &cancellables)
        link.onMessage = { [weak self] message, _ in self?.handle(message) }
        link.onResourceStarted = { [weak self] name, _ in self?.statusMessage = "Получаю \(name)…" }
        link.onResource = { [weak self] url, _ in
            self?.statusMessage = nil
            self?.deliver(.file(url))
        }

        let tracker = tracker
        camera.onFrame = { [weak self] pixelBuffer in
            // Распознаём только пока палец на экране — экономим батарею.
            guard self?.isAimingSnapshot == true else { return }
            let point = tracker.process(pixelBuffer)
            let markers = tracker.visibleMarkers
            DispatchQueue.main.async { self?.update(point: point, markers: markers) }
        }
    }

    func start() {
        camera.start()
        link.start()
    }

    func beginAim() {
        guard !isAiming else { return }
        guard macName != nil else {
            statusMessage = "Mac не найден. Запусти Draca на Mac."
            return
        }
        isAiming = true
        isAimingSnapshot = true
        tracker.reset()
        lastPoint = nil
        statusMessage = nil
        aimState = .searching
        haptics.prepare()
        link.send(.aimStart)
    }

    func endAim() {
        guard isAiming else { return }
        isAiming = false
        isAimingSnapshot = false
        aimState = .idle
        visibleMarkers = 0
        // Берём точку, только если экран был в прицеле совсем недавно.
        if let point = lastPoint, Date().timeIntervalSince(lastPointDate) < 0.4 {
            link.send(.pick(x: point.x, y: point.y))
            statusMessage = "Запрашиваю у Mac…"
        } else {
            link.send(.aimCancel)
        }
    }

    /// Читается с очереди камеры, поэтому вне главного актора.
    nonisolated(unsafe) private var isAimingSnapshot = false

    private func update(point: CGPoint?, markers: Int) {
        guard isAiming else { return }
        visibleMarkers = markers
        if let point {
            if aimState != .locked { haptics.impactOccurred(intensity: 0.5) }
            aimState = .locked
            lastPoint = point
            lastPointDate = Date()
            link.send(.aim(x: point.x, y: point.y), reliable: false)
        } else if aimState == .locked {
            aimState = .searching
            link.send(.aimLost)
        }
    }

    private func handle(_ message: DracaMessage) {
        switch message {
        case let .link(string):
            statusMessage = nil
            if let url = URL(string: string) { deliver(.link(url)) }
        case let .pickFailed(reason):
            statusMessage = reason
        default:
            break
        }
    }

    private func deliver(_ kind: ReceivedItem.Kind) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        received = ReceivedItem(kind: kind)
    }
}
