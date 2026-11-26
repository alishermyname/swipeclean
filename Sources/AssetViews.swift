import SwiftUI
import Photos
import AVKit

enum ImageLoader {
    static let manager = PHCachingImageManager()
}

/// Картинка из галереи (сначала быстрая превью, потом чёткая).
struct AssetImage: View {
    let asset: PHAsset
    var targetSize: CGSize
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color(.secondarySystemBackground))
                ProgressView()
            }
        }
        .task(id: asset.localIdentifier) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            ImageLoader.manager.requestImage(for: asset,
                                             targetSize: targetSize,
                                             contentMode: contentMode == .fit ? .aspectFit : .aspectFill,
                                             options: options) { result, _ in
                if let result { image = result }
            }
        }
    }
}

struct VideoPlayerView: View {
    let asset: PHAsset
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                AssetImage(asset: asset, targetSize: CGSize(width: 1200, height: 1800), contentMode: .fit)
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard let item else { return }
                DispatchQueue.main.async {
                    let p = AVPlayer(playerItem: item)
                    player = p
                    p.play()
                }
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

/// Карточка для свайпа.
struct CardView: View {
    let asset: PHAsset
    var isActive: Bool
    @State private var size: Int64?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
            if asset.mediaType == .video && isActive {
                VideoPlayerView(asset: asset)
            } else {
                AssetImage(asset: asset, targetSize: CGSize(width: 1290, height: 1800), contentMode: .fit)
            }
            infoBar
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        .task(id: asset.localIdentifier) {
            let a = asset
            size = await Task.detached { Library.fileSize(a) }.value
        }
    }

    private var infoBar: some View {
        HStack(spacing: 8) {
            if asset.mediaType == .video {
                Label(Library.formatDuration(asset.duration), systemImage: "video.fill")
            }
            if let date = asset.creationDate {
                Text(date.formatted(date: .abbreviated, time: .shortened))
            }
            Spacer()
            if let size {
                Text(Library.formatBytes(size)).bold()
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45))
    }
}

/// Сетка для «Потом» и «Корзины».
struct GridCell: View {
    let asset: PHAsset

    var body: some View {
        Color.clear
            .frame(height: 120)
            .overlay(AssetImage(asset: asset, targetSize: CGSize(width: 360, height: 360)))
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Text(Library.formatDuration(asset.duration))
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
    }
}

struct PreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct PreviewSheet: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if asset.mediaType == .video {
                    VideoPlayerView(asset: asset)
                } else {
                    AssetImage(asset: asset, targetSize: CGSize(width: 2000, height: 2000), contentMode: .fit)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
