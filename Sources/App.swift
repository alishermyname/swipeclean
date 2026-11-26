import SwiftUI
import Photos

@main
struct SwipeCleanApp: App {
    @StateObject private var store = DecisionStore()
    @StateObject private var scanner = SimilarScanner()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(scanner)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: DecisionStore
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        if status == .authorized || status == .limited {
            TabView {
                NavigationStack { SwipeView(mode: .library) }
                    .tabItem { Label("Разбор", systemImage: "hand.draw") }

                NavigationStack { SimilarView() }
                    .tabItem { Label("Похожие", systemImage: "square.on.square") }

                NavigationStack { QueueView(decision: .later) }
                    .tabItem { Label("Потом", systemImage: "clock") }
                    .badge(store.count(.later))

                NavigationStack { QueueView(decision: .delete) }
                    .tabItem { Label("Корзина", systemImage: "trash") }
                    .badge(store.count(.delete))
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Чистка галереи")
                    .font(.largeTitle.bold())
                Text("Свайп влево - удалить, вправо - оставить, вверх - потом. Всё работает на телефоне, ничего никуда не отправляется.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if status == .notDetermined {
                    Button("Дать доступ к галерее") {
                        Task { status = await Library.requestAccess() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Доступ запрещён. Разреши «Полный доступ» в настройках.")
                        .font(.footnote)
                    Button("Открыть настройки") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(32)
        }
    }
}
