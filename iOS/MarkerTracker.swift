import CoreVideo
import Vision

/// Находит QR-маркеры Mac в кадре и вычисляет, в какую точку экрана смотрит центр камеры.
/// Работает на очереди камеры.
final class MarkerTracker {
    private let request: VNDetectBarcodesRequest = {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        return request
    }()
    private var smoothed: CGPoint?

    /// Сколько маркеров видно в последнем кадре — для подсказки в UI.
    private(set) var visibleMarkers = 0

    func reset() {
        smoothed = nil
        visibleMarkers = 0
    }

    /// Точка прицела в нормализованных координатах экрана Mac или nil, если экран не найден.
    func process(_ pixelBuffer: CVPixelBuffer) -> CGPoint? {
        // Ориентацию не передаём: гомография сама учтёт поворот, а центр кадра от поворота не зависит.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])

        var imagePoints: [CGPoint] = []
        var screenPoints: [CGPoint] = []
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue,
                  let marker = MarkerPayload.decode(payload) else { continue }
            let corners = [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight]
            imagePoints.append(CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4))
            screenPoints.append(marker.center)
        }
        visibleMarkers = imagePoints.count

        guard let homography = Homography(from: imagePoints, to: screenPoints),
              let raw = homography.apply(CGPoint(x: 0.5, y: 0.5)),
              (-0.05...1.05).contains(raw.x), (-0.05...1.05).contains(raw.y) else {
            smoothed = nil
            return nil
        }

        // Лёгкое сглаживание, чтобы прицел на Mac не дрожал.
        let point = smoothed.map { CGPoint(x: $0.x + (raw.x - $0.x) * 0.5, y: $0.y + (raw.y - $0.y) * 0.5) } ?? raw
        smoothed = point
        return CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))
    }
}
