import SwiftUI
import Photos

struct SimilarView: View {
    @EnvironmentObject var scanner: SimilarScanner
    @EnvironmentObject var store: DecisionStore
    @State private var preview: PreviewItem?
    @State private var deleting = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                if scanner.scanning {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ищу похожие… \(Int(scanner.progress * 100))%")
                        ProgressView(value: scanner.progress)
                        Text("Первый раз может занять несколько минут. Потом быстрее - результаты запоминаются.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        scanner.scan()
                    } label: {
                        Label(scanner.scannedTotal == 0 ? "Найти похожие фото" : "Сканировать заново",
                              systemImage: "sparkle.magnifyingglass")
                    }
                }

                if scanner.scannedTotal > 0 && !scanner.scanning {
                    summary
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Чувствительность")
                            Spacer()
                            if scanner.regrouping { ProgressView() }
                            Text(String(format: "%.2f", scanner.threshold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $scanner.threshold, in: 0.15...0.8, step: 0.05, onEditingChanged: { editing in
                            if !editing { Task { await scanner.regroup() } }
                        })
                        Text("Левее - только почти одинаковые. Правее - просто похожие.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(scanner.groups) { group in
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.assets, id: \.localIdentifier) { asset in
                                thumb(asset, group: group)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                } header: {
                    Text(header(group))
                }
            }

            if !scanner.groups.isEmpty {
                Color.clear.frame(height: 70).listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Похожие")
        .safeAreaInset(edge: .bottom) {
            if !scanner.selected.isEmpty && !scanner.scanning {
                Button {
                    deleting = true
                    Task {
                        let (deleted, error) = await scanner.deleteSelected()
                        store.remove(deleted)
                        errorText = error
                        deleting = false
                    }
                } label: {
                    Text(deleting ? "Удаляю…" : "Удалить отмеченные: \(scanner.selected.count) • \(Library.formatBytes(scanner.selectedBytes))")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(deleting)
                .padding()
                .background(.bar)
            }
        }
        .sheet(item: $preview) { PreviewSheet(asset: $0.asset) }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Проверено фото: \(scanner.scannedTotal)")
            Text("Групп похожих: \(scanner.groups.count)").bold()
            Text("В них фото: \(scanner.photosInGroups), лишних примерно: \(scanner.extraCount)")
            Text("Если удалить отмеченные - освободится ~\(Library.formatBytes(scanner.selectedBytes))")
                .foregroundStyle(.secondary)
            Text("Зелёная галочка - оставить, красная корзина - удалить. Нажми, чтобы переключить. Удержи - открыть.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func header(_ group: SimilarGroup) -> String {
        let date = group.assets.first?.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let marked = group.assets.filter { scanner.selected.contains($0.localIdentifier) }.count
        return "\(group.assets.count) похожих • \(date) • удалить: \(marked)"
    }

    private func thumb(_ asset: PHAsset, group: SimilarGroup) -> some View {
        let id = asset.localIdentifier
        let isSelected = scanner.selected.contains(id)
        return Color.clear
            .frame(width: 110, height: 146)
            .overlay(AssetImage(asset: asset, targetSize: CGSize(width: 330, height: 440)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.red : Color.clear, lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSelected ? "trash.circle.fill" : "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.red : Color.green)
                    .font(.title2)
                    .padding(4)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    if id == group.best {
                        Text("лучшее")
                            .font(.caption2.bold())
                    }
                    if let size = scanner.sizes[id] {
                        Text(Library.formatBytes(size))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .padding(4)
            }
            .contentShape(Rectangle())
            .onTapGesture { scanner.toggle(id) }
            .onLongPressGesture { preview = PreviewItem(asset: asset) }
    }
}
