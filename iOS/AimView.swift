import SwiftUI

struct AimView: View {
    @StateObject private var model = PhoneModel()

    var body: some View {
        ZStack {
            CameraPreview(session: model.camera.session)
                .ignoresSafeArea()

            Crosshair(state: model.aimState)

            VStack {
                StatusPill(macName: model.macName)
                Spacer()
                Text(hint)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.beginAim() }
                .onEnded { _ in model.endAim() }
        )
        .sheet(item: $model.received) { ReceivedView(item: $0) }
        .onAppear { model.start() }
    }

    private var hint: String {
        if let message = model.statusMessage { return message }
        switch model.aimState {
        case .idle: return "Держи палец и наведи прицел на то, что хочешь забрать с Mac"
        case .searching: return model.visibleMarkers > 0 ? "Вижу маркеров: \(model.visibleMarkers) из 4+ нужных" : "Ищу экран Mac…"
        case .locked: return "Отпусти, чтобы забрать"
        }
    }
}

private struct Crosshair: View {
    let state: PhoneModel.AimState

    var body: some View {
        let color: Color = state == .locked ? .green : .white
        ZStack {
            Circle().stroke(color, lineWidth: 3).frame(width: 64, height: 64)
            Rectangle().fill(color).frame(width: 2, height: 20)
            Rectangle().fill(color).frame(width: 20, height: 2)
        }
        .shadow(radius: 3)
        .scaleEffect(state == .locked ? 1.15 : 1)
        .animation(.spring(duration: 0.2), value: state)
    }
}

private struct StatusPill: View {
    let macName: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(macName == nil ? Color.orange : Color.green).frame(width: 8, height: 8)
            Text(macName.map { "Mac: \($0)" } ?? "Ищу Mac…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.top, 8)
    }
}

private struct ReceivedView: View {
    let item: ReceivedItem

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch item.kind {
                case let .file(url):
                    if let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "doc.fill").font(.system(size: 64)).foregroundStyle(.secondary)
                    }
                    Text(url.lastPathComponent).font(.headline).multilineTextAlignment(.center)
                    ShareLink(item: url) { Label("Сохранить или отправить", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                case let .link(url):
                    Image(systemName: "link").font(.system(size: 48)).foregroundStyle(.tint)
                    Text(url.absoluteString).font(.callout).multilineTextAlignment(.center).textSelection(.enabled)
                    Link("Открыть", destination: url).buttonStyle(.borderedProminent)
                    ShareLink(item: url)
                }
            }
            .padding(16)
            .navigationTitle("С Mac")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
