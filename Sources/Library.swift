import Photos
import UIKit

enum MediaFilter: String, CaseIterable, Identifiable {
    case all = "Всё"
    case photos = "Фото"
    case videos = "Видео"
    case screenshots = "Скрины"
    var id: String { rawValue }
}

enum Library {
    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func fetch(filter: MediaFilter, newestFirst: Bool) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: !newestFirst)]
        let result: PHFetchResult<PHAsset>
        switch filter {
        case .all:
            options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                            PHAssetMediaType.image.rawValue,
                                            PHAssetMediaType.video.rawValue)
            result = PHAsset.fetchAssets(with: options)
        case .photos:
            result = PHAsset.fetchAssets(with: .image, options: options)
        case .videos:
            result = PHAsset.fetchAssets(with: .video, options: options)
        case .screenshots:
            let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                 subtype: .smartAlbumScreenshots,
                                                                 options: nil)
            guard let album = albums.firstObject else { return [] }
            result = PHAsset.fetchAssets(in: album, options: options)
        }
        return toArray(result)
    }

    static func assets(ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return toArray(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options))
    }

    private static func toArray(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    /// Реальный размер на диске (включая видео-часть Live Photo и оригиналы правок).
    static func fileSize(_ asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset).reduce(Int64(0)) { sum, resource in
            sum + ((resource.value(forKey: "fileSize") as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func totalSize(_ assets: [PHAsset]) -> Int64 {
        assets.reduce(Int64(0)) { $0 + fileSize($1) }
    }

    /// Удаление. iOS сама покажет окно подтверждения, файлы уйдут в «Недавно удалённые» на 30 дней.
    static func delete(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    static func isUserCancel(_ error: Error) -> Bool {
        (error as NSError).code == 3072
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let t = Int(seconds.rounded())
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
