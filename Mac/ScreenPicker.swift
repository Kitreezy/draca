import AppKit
import ApplicationServices
import ScreenCaptureKit
import UniformTypeIdentifiers

enum PickedItem {
    case file(URL)
    case link(URL)
}

enum PickError: LocalizedError {
    case noScreen
    case nothingUnderPoint
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .noScreen: "Экран не найден"
        case .nothingUnderPoint: "Под прицелом нет окна"
        case .captureFailed: "Не удалось снять окно"
        }
    }
}

/// Решает, что отдать по точке на экране:
/// 1. файл или ссылка под прицелом (через Accessibility — Finder, браузеры);
/// 2. иначе — снимок окна под прицелом.
@MainActor
final class ScreenPicker {
    func pick(atNormalized point: CGPoint) async throws -> PickedItem {
        guard let screen = NSScreen.screens.first else { throw PickError.noScreen }
        // Глобальные координаты CG: начало — левый верхний угол главного экрана.
        let global = CGPoint(x: point.x * screen.frame.width, y: point.y * screen.frame.height)

        if let url = urlUnderPoint(global) {
            return url.isFileURL ? .file(url) : .link(url)
        }
        return .file(try await captureWindow(at: global))
    }

    // MARK: - Accessibility

    private func urlUnderPoint(_ point: CGPoint) -> URL? {
        guard AXIsProcessTrusted() else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              var current = element else { return nil }

        // Поднимаемся по иерархии: URL обычно висит на строке/ячейке файла или на ссылке.
        for _ in 0..<6 {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, kAXURLAttribute as CFString, &value) == .success,
               let url = (value as? NSURL) as URL?,
               isSendable(url) {
                return url
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            current = parent as! AXUIElement
        }
        return nil
    }

    private func isSendable(_ url: URL) -> Bool {
        if url.isFileURL {
            // Папки MultipeerConnectivity не передаёт — их пропускаем.
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        return url.scheme == "http" || url.scheme == "https"
    }

    // MARK: - Снимок окна

    private func captureWindow(at point: CGPoint) async throws -> URL {
        guard let windowID = frontWindowID(at: point) else { throw PickError.nothingUnderPoint }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw PickError.nothingUnderPoint }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        let appName = (window.owningApplication?.applicationName ?? "Окно").replacingOccurrences(of: "/", with: "-")
        let stamp = Date().formatted(.dateTime.hour().minute().second()).replacingOccurrences(of: ":", with: ".")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(appName) \(stamp).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PickError.captureFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PickError.captureFailed }
        return url
    }

    /// Верхнее обычное окно под точкой. CGWindowList отдаёт окна сверху вниз.
    private func frontWindowID(at point: CGPoint) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let myPID = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != myPID,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(point),
                  let number = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            return number
        }
        return nil
    }
}
