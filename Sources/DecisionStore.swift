import Foundation
import Photos

enum Decision: String, Codable {
    case keep    // оставить навсегда
    case later   // отложить на потом
    case delete  // в корзину (удалится по кнопке)
}

@MainActor
final class DecisionStore: ObservableObject {
    @Published private(set) var decisions: [String: Decision] = [:]
    /// Растёт при каждом изменении - удобно для .task(id:)
    @Published private(set) var version = 0

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("decisions.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Decision].self, from: data) {
            decisions = saved
        }
    }

    func set(_ id: String, _ decision: Decision?) {
        decisions[id] = decision
        save()
    }

    func ids(_ decision: Decision) -> [String] {
        decisions.compactMap { $0.value == decision ? $0.key : nil }
    }

    func count(_ decision: Decision) -> Int {
        decisions.values.reduce(0) { $0 + ($1 == decision ? 1 : 0) }
    }

    func remove(_ ids: [String]) {
        for id in ids { decisions[id] = nil }
        save()
    }

    func clear(_ decision: Decision) {
        decisions = decisions.filter { $0.value != decision }
        save()
    }

    /// Удалить всё, что лежит в корзине. Возвращает текст ошибки или nil.
    func deleteQueued() async -> String? {
        let queued = self.ids(.delete)
        let assets = Library.assets(ids: queued)
        guard !assets.isEmpty else {
            remove(queued)
            return nil
        }
        do {
            try await Library.delete(assets)
            remove(queued)
            return nil
        } catch {
            return Library.isUserCancel(error) ? nil : error.localizedDescription
        }
    }

    private func save() {
        version += 1
        if let data = try? JSONEncoder().encode(decisions) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
