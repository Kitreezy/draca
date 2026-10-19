import SwiftUI

@main
struct DracaMacApp: App {
    @StateObject private var model = MacModel()

    var body: some Scene {
        MenuBarExtra("Draca", systemImage: "scope") {
            MenuContent(model: model)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: MacModel

    var body: some View {
        Text(model.peerNames.isEmpty ? "iPhone не подключён" : "Подключено: \(model.peerNames.joined(separator: ", "))")
        Text(model.lastEvent)
        Divider()
        Picker("Размер маркеров", selection: $model.markerSize) {
            ForEach(MarkerSize.allCases) { Text($0.title).tag($0) }
        }
        Button(model.isOverlayVisible ? "Скрыть маркеры" : "Показать маркеры (тест)") { model.toggleOverlay() }
        Divider()
        Button("Разрешить доступ к файлам под прицелом…") { model.requestAccessibility() }
        Divider()
        Button("Выйти") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
