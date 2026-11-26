import SwiftUI
import Photos

enum DeckMode { case library, later }

private struct HistoryItem {
    let asset: PHAsset
    let previous: Decision?
}

struct SwipeView: View {
    @EnvironmentObject var store: DecisionStore
    var mode: DeckMode = .library

    @State private var deck: [PHAsset] = []
    @State private var index = 0
    @State private var filter: MediaFilter = .all
    @State private var newestFirst = true
    @State private var offset: CGSize = .zero
    @State private var history: [HistoryItem] = []
    @State private var loading = true
    @State private var animating = false
    @State private var deleting = false
    @State private var errorText: String?

    private var current: PHAsset? { index < deck.count ? deck[index] : nil }
    private var next: PHAsset? { index + 1 < deck.count ? deck[index + 1] : nil }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Тип", selection: $filter) {
                ForEach(MediaFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            ZStack {
                if loading {
                    ProgressView()
                } else if let current {
                    if let next {
                        CardView(asset: next, isActive: false)
                            .id(next.localIdentifier)
                            .scaleEffect(0.94)
                            .opacity(0.8)
                    }
                    CardView(asset: current, isActive: true)
                        .id(current.localIdentifier)
                        .overlay(stamp)
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 25)))
                        .highPriorityGesture(drag)
                } else {
                    ContentUnavailableView("Всё разобрано",
                                           systemImage: "checkmark.seal",
                                           description: Text(mode == .library
                                                             ? "Тут пусто. Загляни в «Корзину», чтобы реально освободить место."
                                                             : "Отложенных больше нет."))
                }
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

            Text("← удалить    ↑ потом    оставить →")
                .font(.caption)
                .foregroundStyle(.secondary)

            buttons
            trashBar
        }
        .padding(.bottom, 8)
        .navigationTitle(mode == .library ? "Разбор" : "Отложенные")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text("Осталось: \(max(deck.count - index, 0))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Сначала новые", isOn: $newestFirst)
                    if mode == .library {
                        Button("Показать снова «оставленные»", role: .destructive) {
                            store.clear(.keep)
                            reload()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear { reload() }
        .onChange(of: filter) { reload() }
        .onChange(of: newestFirst) { reload() }
    }

    // MARK: - Карточка

    private var drag: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                if !animating { offset = value.translation }
            }
            .onEnded { value in
                let t = value.translation
                if t.width < -110 {
                    fling(.delete, to: CGSize(width: -700, height: t.height))
                } else if t.width > 110 {
                    fling(.keep, to: CGSize(width: 700, height: t.height))
                } else if t.height < -130 {
                    fling(.later, to: CGSize(width: t.width, height: -1100))
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero }
                }
            }
    }

    private var stamp: some View {
        let isUp = offset.height < -60 && abs(offset.height) > abs(offset.width)
        let text = isUp ? "ПОТОМ" : (offset.width < 0 ? "УДАЛИТЬ" : "ОСТАВИТЬ")
        let color: Color = isUp ? .orange : (offset.width < 0 ? .red : .green)
        let strength = min(1, max(abs(offset.width), -offset.height) / 110)
        return Text(text)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(-12))
            .padding(.top, 60)
            .opacity(Double(strength))
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
    }

    private var buttons: some View {
        HStack(spacing: 26) {
            roundButton("arrow.uturn.backward", .gray, size: 48) { undo() }
                .disabled(history.isEmpty)
                .opacity(history.isEmpty ? 0.4 : 1)
            roundButton("xmark", .red) { fling(.delete, to: CGSize(width: -700, height: 0)) }
            roundButton("clock", .orange) { fling(.later, to: CGSize(width: 0, height: -1100)) }
            roundButton("checkmark", .green) { fling(.keep, to: CGSize(width: 700, height: 0)) }
        }
        .disabled(current == nil)
    }

    private func roundButton(_ icon: String, _ color: Color, size: CGFloat = 62, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Circle().fill(Color(.secondarySystemBackground)))
                .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 2))
        }
    }

    @ViewBuilder
    private var trashBar: some View {
        let n = store.count(.delete)
        if n > 0 {
            HStack {
                Image(systemName: "trash")
                Text("В корзине: \(n)")
                Spacer()
                Button(deleting ? "Удаляю…" : "Удалить сейчас") {
                    deleting = true
                    Task {
                        errorText = await store.deleteQueued()
                        deleting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(deleting)
            }
            .font(.footnote)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .padding(.horizontal)
        }
    }

    // MARK: - Логика

    private func fling(_ decision: Decision, to target: CGSize) {
        guard let asset = current, !animating else { return }
        animating = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.2)) { offset = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            history.append(HistoryItem(asset: asset, previous: store.decisions[asset.localIdentifier]))
            if history.count > 50 { history.removeFirst() }
            store.set(asset.localIdentifier, decision)
            offset = .zero
            index += 1
            animating = false
        }
    }

    private func undo() {
        guard let item = history.popLast() else { return }
        store.set(item.asset.localIdentifier, item.previous)
        if index > 0, deck[index - 1].localIdentifier == item.asset.localIdentifier {
            index -= 1
        } else {
            deck.insert(item.asset, at: min(index, deck.count))
        }
        offset = .zero
    }

    private func reload() {
        loading = true
        let filter = filter
        let newest = newestFirst
        let mode = mode
        let decisions = store.decisions
        Task {
            let assets = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
                let all = Library.fetch(filter: filter, newestFirst: newest)
                switch mode {
                case .library: return all.filter { decisions[$0.localIdentifier] == nil }
                case .later: return all.filter { decisions[$0.localIdentifier] == .later }
                }
            }.value
            deck = assets
            index = 0
            history = []
            offset = .zero
            loading = false
        }
    }
}
