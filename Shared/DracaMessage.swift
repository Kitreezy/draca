import Foundation

enum DracaConfig {
    /// Тип сервиса MultipeerConnectivity: до 15 символов, a-z, 0-9, дефис.
    static let serviceType = "draca-aim"
    static let markerPrefix = "DRACA"
}

/// Сообщения между iPhone и Mac.
/// Координаты нормализованы к экрану Mac: (0, 0) — левый верхний угол, (1, 1) — правый нижний.
enum DracaMessage: Codable {
    // iPhone → Mac
    case aimStart
    case aim(x: Double, y: Double)
    case aimLost
    case pick(x: Double, y: Double)
    case aimCancel

    // Mac → iPhone
    case link(url: String)
    case pickFailed(reason: String)
}

/// Содержимое QR-маркера: "DRACA|<сессия>|<x>|<y>", где x, y — центр маркера на экране Mac.
enum MarkerPayload {
    static func encode(session: String, center: CGPoint) -> String {
        String(format: "%@|%@|%.4f|%.4f", DracaConfig.markerPrefix, session, center.x, center.y)
    }

    static func decode(_ string: String) -> (session: String, center: CGPoint)? {
        let parts = string.split(separator: "|")
        guard parts.count == 4, parts[0] == DracaConfig.markerPrefix,
              let x = Double(parts[2]), let y = Double(parts[3]) else { return nil }
        return (String(parts[1]), CGPoint(x: x, y: y))
    }
}
