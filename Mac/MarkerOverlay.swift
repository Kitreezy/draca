import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Прозрачное окно поверх всего на главном экране: 8 QR-маркеров по краям и кольцо прицела.
@MainActor
final class MarkerOverlay {
    final class State: ObservableObject {
        @Published var reticle: CGPoint?
        @Published var markerSize: CGFloat = 150
        @Published var topInset: CGFloat = 12
        /// Случайный id сессии: по нему iPhone поймёт, на какой Mac смотрит.
        let session = String(UUID().uuidString.prefix(4)).lowercased()
    }

    let state = State()
    private var window: NSWindow?

    func show() {
        guard let screen = NSScreen.screens.first else { return }
        state.reticle = nil
        state.topInset = max(12, screen.safeAreaInsets.top + 8)
        let window = self.window ?? makeWindow()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
    }

    func hide() {
        window?.orderOut(nil)
        state.reticle = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: OverlayView(state: state))
        return window
    }
}

private struct OverlayView: View {
    @ObservedObject var state: MarkerOverlay.State

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(Array(markerCenters(in: size).enumerated()), id: \.offset) { _, center in
                    QRMarker(payload: MarkerPayload.encode(
                        session: state.session,
                        center: CGPoint(x: center.x / size.width, y: center.y / size.height)
                    ), size: state.markerSize)
                    .position(center)
                }
                if let reticle = state.reticle {
                    Reticle()
                        .position(x: reticle.x * size.width, y: reticle.y * size.height)
                        .animation(.easeOut(duration: 0.08), value: reticle)
                }
            }
        }
    }

    /// Углы и середины сторон. Центр экрана не занимаем — там то, во что целятся.
    private func markerCenters(in size: CGSize) -> [CGPoint] {
        let half = state.markerSize / 2
        let left = half + 12, right = size.width - half - 12
        let top = half + state.topInset, bottom = size.height - half - 12
        let midX = size.width / 2, midY = size.height / 2
        return [
            CGPoint(x: left, y: top), CGPoint(x: midX, y: top), CGPoint(x: right, y: top),
            CGPoint(x: left, y: midY), CGPoint(x: right, y: midY),
            CGPoint(x: left, y: bottom), CGPoint(x: midX, y: bottom), CGPoint(x: right, y: bottom),
        ]
    }
}

private struct QRMarker: View {
    let payload: String
    let size: CGFloat

    var body: some View {
        if let image = QRCache.image(for: payload) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .padding(size * 0.1) // «тихая зона» вокруг QR
                .frame(width: size, height: size)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct Reticle: View {
    var body: some View {
        ZStack {
            Circle().stroke(Color.accentColor, lineWidth: 4).frame(width: 56, height: 56)
            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
        }
        .shadow(radius: 4)
    }
}

private enum QRCache {
    private static var cache: [String: CGImage] = [:]
    private static let context = CIContext()

    static func image(for payload: String) -> CGImage? {
        if let cached = cache[payload] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "L" // меньше модулей — легче читать издалека
        guard let output = filter.outputImage,
              let image = context.createCGImage(output, from: output.extent) else { return nil }
        cache[payload] = image
        return image
    }
}
