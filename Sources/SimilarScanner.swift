import Foundation
import Photos
import Vision
import UIKit
import Accelerate

struct SimilarGroup: Identifiable {
    let id: String
    var assets: [PHAsset]
    var best: String
}

struct ScanResult {
    var ids: [String] = []
    var vectors: [[Float]?] = []
    var hashes: [UInt64] = []
}

private struct PrintEntry: Codable {
    var vector: Data
    var hash: Int64
}

/// Кэш «отпечатков» фото, чтобы повторное сканирование было быстрым.
private enum PrintCache {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("prints-v1.plist")
    }

    static func load() -> [String: PrintEntry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? PropertyListDecoder().decode([String: PrintEntry].self, from: data)) ?? [:]
    }

    static func save(_ cache: [String: PrintEntry]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(cache) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Вся тяжёлая работа - вне главного потока.
enum SimilarEngine {
    static func scan(progress: (Double) -> Void) -> ScanResult {
        let assets = Library.fetch(filter: .photos, newestFirst: false) // по дате, от старых к новым
        let oldCache = PrintCache.load()
        var cache: [String: PrintEntry] = [:]
        var result = ScanResult()
        result.ids.reserveCapacity(assets.count)

        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false // только то, что уже есть на телефоне

        var newSinceSave = 0
        for (i, asset) in assets.enumerated() {
            let key = asset.localIdentifier + "|" + String(Int(asset.modificationDate?.timeIntervalSince1970 ?? 0))
            result.ids.append(asset.localIdentifier)

            if let entry = oldCache[key] {
                cache[key] = entry
                result.vectors.append(floats(entry.vector))
                result.hashes.append(UInt64(bitPattern: entry.hash))
            } else {
                let computed: ([Float], UInt64)? = autoreleasepool {
                    var cgImage: CGImage?
                    manager.requestImage(for: asset,
                                         targetSize: CGSize(width: 300, height: 300),
                                         contentMode: .aspectFill,
                                         options: options) { image, _ in
                        cgImage = image?.cgImage
                    }
                    guard let cg = cgImage, let vector = featureVector(cg) else { return nil }
                    return (vector, dHash(cg))
                }
                if let computed {
                    let (vector, hash) = computed
                    cache[key] = PrintEntry(vector: vector.withUnsafeBufferPointer { Data(buffer: $0) },
                                            hash: Int64(bitPattern: hash))
                    result.vectors.append(vector)
                    result.hashes.append(hash)
                    newSinceSave += 1
                } else {
                    result.vectors.append(nil)
                    result.hashes.append(0)
                }
            }

            if i % 40 == 0 { progress(Double(i) / Double(max(assets.count, 1))) }
            if newSinceSave >= 1500 {
                PrintCache.save(cache.merging(oldCache) { new, _ in new })
                newSinceSave = 0
            }
        }
        PrintCache.save(cache)
        progress(1)
        return result
    }

    static func buildGroups(_ r: ScanResult, threshold: Float, window: Int = 6) -> ([SimilarGroup], [String: Int64]) {
        let n = r.ids.count
        var parent = Array(0..<n)

        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
        }

        // 1) Похожие по смыслу среди соседних по времени снимков (серии, дубли кадра)
        let t2 = threshold * threshold
        for i in 0..<n {
            guard let vi = r.vectors[i] else { continue }
            for j in max(0, i - window)..<i {
                guard let vj = r.vectors[j], vj.count == vi.count else { continue }
                var d: Float = 0
                vDSP_distancesq(vi, 1, vj, 1, &d, vDSP_Length(vi.count))
                if d < t2 { union(i, j) }
            }
        }

        // 2) Точные копии в любом месте галереи (одинаковый dHash)
        var byHash: [UInt64: Int] = [:]
        for i in 0..<n {
            let h = r.hashes[i]
            if h == 0 || h == UInt64.max { continue } // однотонные картинки не считаем
            if let j = byHash[h] { union(i, j) } else { byHash[h] = i }
        }

        var buckets: [Int: [Int]] = [:]
        for i in 0..<n { buckets[find(i), default: []].append(i) }
        let rawGroups = buckets.values.filter { $0.count > 1 }

        let allIds = rawGroups.flatMap { $0.map { r.ids[$0] } }
        var assetById: [String: PHAsset] = [:]
        for a in Library.assets(ids: allIds) { assetById[a.localIdentifier] = a }

        var sizes: [String: Int64] = [:]
        var groups: [SimilarGroup] = []
        for g in rawGroups {
            let assets = g.compactMap { assetById[r.ids[$0]] }
                .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
            guard assets.count > 1 else { continue }
            for a in assets { sizes[a.localIdentifier] = Library.fileSize(a) }
            // «Лучшее»: избранное, потом самое большое разрешение, потом самый тяжёлый файл
            let best = assets.max { a, b in
                if a.isFavorite != b.isFavorite { return !a.isFavorite }
                let pa = a.pixelWidth * a.pixelHeight, pb = b.pixelWidth * b.pixelHeight
                if pa != pb { return pa < pb }
                return (sizes[a.localIdentifier] ?? 0) < (sizes[b.localIdentifier] ?? 0)
            }!
            groups.append(SimilarGroup(id: assets[0].localIdentifier, assets: assets, best: best.localIdentifier))
        }
        groups.sort { ($0.assets[0].creationDate ?? .distantPast) > ($1.assets[0].creationDate ?? .distantPast) }
        return (groups, sizes)
    }

    // MARK: - Vision + хэш

    static func featureVector(_ cg: CGImage) -> [Float]? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return nil }
        guard let obs = request.results?.first else { return nil }

        let count = obs.elementCount
        var v = [Float](repeating: 0, count: count)
        obs.data.withUnsafeBytes { raw in
            switch obs.elementType {
            case .float:
                for i in 0..<count { v[i] = raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self) }
            case .double:
                for i in 0..<count { v[i] = Float(raw.loadUnaligned(fromByteOffset: i * 8, as: Double.self)) }
            default:
                break
            }
        }
        // нормализуем, чтобы расстояние было в понятном диапазоне 0...2
        var norm: Float = 0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        guard norm > 0 else { return nil }
        for i in 0..<count { v[i] /= norm }
        return v
    }

    static func dHash(_ cg: CGImage) -> UInt64 {
        let w = 9, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h)
        pixels.withUnsafeMutableBytes { buf in
            if let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue) {
                ctx.interpolationQuality = .medium
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        var hash: UInt64 = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                hash <<= 1
                if pixels[y * w + x] > pixels[y * w + x + 1] { hash |= 1 }
            }
        }
        return hash
    }

    static func floats(_ data: Data) -> [Float] {
        let n = data.count / MemoryLayout<Float>.size
        return [Float](unsafeUninitializedCapacity: n) { buffer, initialized in
            _ = data.copyBytes(to: buffer)
            initialized = n
        }
    }
}

@MainActor
final class SimilarScanner: ObservableObject {
    @Published var groups: [SimilarGroup] = []
    @Published var selected: Set<String> = []
    @Published var sizes: [String: Int64] = [:]
    @Published var progress: Double = 0
    @Published var scanning = false
    @Published var regrouping = false
    @Published var scannedTotal = 0
    @Published var threshold: Double = 0.4

    private var result: ScanResult?

    var photosInGroups: Int { groups.reduce(0) { $0 + $1.assets.count } }
    var extraCount: Int { photosInGroups - groups.count }
    var selectedBytes: Int64 { selected.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        progress = 0
        Task {
            let r = await Task.detached(priority: .userInitiated) { () -> ScanResult in
                SimilarEngine.scan { p in
                    Task { @MainActor in self.progress = p }
                }
            }.value
            result = r
            scannedTotal = r.ids.count
            await regroup()
            scanning = false
        }
    }

    func regroup() async {
        guard let r = result else { return }
        regrouping = true
        let t = Float(threshold)
        let (g, s) = await Task.detached(priority: .userInitiated) {
            SimilarEngine.buildGroups(r, threshold: t)
        }.value
        groups = g
        sizes = s
        selected = Set(g.flatMap { group in
            group.assets.map(\.localIdentifier).filter { $0 != group.best }
        })
        regrouping = false
    }

    func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    /// Удаляет отмеченные. Возвращает удалённые id (или nil при отмене/ошибке) и текст ошибки.
    func deleteSelected() async -> (deleted: [String], error: String?) {
        let ids = Array(selected)
        let assets = Library.assets(ids: ids)
        do {
            try await Library.delete(assets)
        } catch {
            return ([], Library.isUserCancel(error) ? nil : error.localizedDescription)
        }
        let gone = Set(ids)
        groups = groups.compactMap { g in
            var g = g
            g.assets.removeAll { gone.contains($0.localIdentifier) }
            return g.assets.count > 1 ? g : nil
        }
        selected.subtract(gone)
        return (ids, nil)
    }
}
