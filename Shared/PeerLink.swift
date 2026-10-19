import Foundation
import MultipeerConnectivity

/// Связь iPhone ↔ Mac поверх MultipeerConnectivity (Wi-Fi peer-to-peer / Bluetooth, без интернета).
/// Mac объявляет себя, iPhone ищет и подключается сам.
/// Прототип: подключение без подтверждения — для реального продукта нужно спаривание.
final class PeerLink: NSObject, ObservableObject {
    enum Role { case advertiser, browser }

    @Published private(set) var connectedPeers: [MCPeerID] = []

    /// Все колбэки вызываются на главной очереди.
    var onMessage: ((DracaMessage, MCPeerID) -> Void)?
    var onResourceStarted: ((String, MCPeerID) -> Void)?
    var onResource: ((URL, MCPeerID) -> Void)?

    private let role: Role
    private let myPeer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(displayName: String, role: Role) {
        self.role = role
        myPeer = MCPeerID(displayName: displayName)
        session = MCSession(peer: myPeer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func start() {
        switch role {
        case .advertiser:
            let advertiser = MCNearbyServiceAdvertiser(peer: myPeer, discoveryInfo: nil, serviceType: DracaConfig.serviceType)
            advertiser.delegate = self
            advertiser.startAdvertisingPeer()
            self.advertiser = advertiser
        case .browser:
            let browser = MCNearbyServiceBrowser(peer: myPeer, serviceType: DracaConfig.serviceType)
            browser.delegate = self
            browser.startBrowsingForPeers()
            self.browser = browser
        }
    }

    func send(_ message: DracaMessage, reliable: Bool = true, to peers: [MCPeerID]? = nil) {
        let targets = peers ?? session.connectedPeers
        guard !targets.isEmpty, let data = try? encoder.encode(message) else { return }
        try? session.send(data, toPeers: targets, with: reliable ? .reliable : .unreliable)
    }

    func sendFile(_ url: URL, to peer: MCPeerID, completion: @escaping (Error?) -> Void) {
        session.sendResource(at: url, withName: url.lastPathComponent, toPeer: peer) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    private func restartBrowsing() {
        guard let browser else { return }
        browser.stopBrowsingForPeers()
        browser.startBrowsingForPeers()
    }
}

extension PeerLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
            if state == .notConnected, self.role == .browser { self.restartBrowsing() }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? decoder.decode(DracaMessage.self, from: data) else { return }
        DispatchQueue.main.async { self.onMessage?(message, peerID) }
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {
        DispatchQueue.main.async { self.onResourceStarted?(resourceName, peerID) }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Временный файл живёт только до выхода из колбэка — переносим сразу.
        guard error == nil, let localURL else { return }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Received", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(resourceName)
        try? FileManager.default.removeItem(at: destination)
        guard (try? FileManager.default.moveItem(at: localURL, to: destination)) != nil else { return }
        DispatchQueue.main.async { self.onResource?(destination, peerID) }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
}

extension PeerLink: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

extension PeerLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
