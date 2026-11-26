import SwiftUI
import Photos

/// Экран «Потом» или «Корзина».
struct QueueView: View {
    @EnvironmentObject var store: DecisionStore
    let decision: Decision

    @State private var assets: [PHAsset] = []
    @State private var totalSize: Int64 = 0
    @State private var deleting = false
    @State private var errorText: String?
    @State private var preview: PreviewItem?

    private var isTrash: Bool { decision == .delete }
    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 2)]

    var body: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView(isTrash ? "Корзина пуста" : "Ничего не отложено",
                                       systemImage: isTrash ? "trash" : "clock",
                                       description: Text(isTrash
                                                         ? "Свайпни фото влево на вкладке «Разбор»."
                                                         : "Свайпни фото вверх на вкладке «Разбор»."))
            } else {
                ScrollView {
                    Text(isTrash
                         ? "Нажми на фото, чтобы вернуть его. Удержи - меню."
                         : "Удержи фото - меню. Или разбери все по одному.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            GridCell(asset: asset)
                                .onTapGesture {
                                    if isTrash { store.set(asset.localIdentifier, nil) }
                                    else { preview = PreviewItem(asset: asset) }
                                }
                                .contextMenu {
                                    Button("Посмотреть", systemImage: "eye") { preview = PreviewItem(asset: asset) }
                                    Button("Вернуть в разбор", systemImage: "arrow.uturn.backward") { store.set(asset.localIdentifier, nil) }
                                    Button("Оставить навсегда", systemImage: "checkmark") { store.set(asset.localIdentifier, .keep) }
                                    if !isTrash {
                                        Button("В корзину", systemImage: "trash", role: .destructive) { store.set(asset.localIdentifier, .delete) }
                                    }
                                }
                        }
                    }
                    Color.clear.frame(height: 90)
                }
            }
        }
        .navigationTitle(isTrash ? "Корзина" : "Потом")
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(item: $preview) { PreviewSheet(asset: $0.asset) }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .task(id: store.version) { await reload() }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if !assets.isEmpty {
            VStack(spacing: 8) {
                if isTrash {
                    Button {
                        deleting = true
                        Task {
                            errorText = await store.deleteQueued()
                            deleting = false
                        }
                    } label: {
                        Text(deleting ? "Удаляю…" : "Удалить всё: \(assets.count) шт. • \(Library.formatBytes(totalSize))")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(deleting)
                    Text("После удаления файлы 30 дней лежат в «Недавно удалённых».")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        SwipeView(mode: .later)
                    } label: {
                        Text("Разобрать по одному: \(assets.count) шт. • \(Library.formatBytes(totalSize))")
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .padding()
            .background(.bar)
        }
    }

    private func reload() async {
        let ids = store.ids(decision)
        let loaded = await Task.detached { Library.assets(ids: ids) }.value
        assets = loaded
        totalSize = await Task.detached { Library.totalSize(loaded) }.value
    }
}
