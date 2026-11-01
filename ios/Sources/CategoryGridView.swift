import SwiftUI
import UIKit

struct CategoryGridView: UIViewRepresentable {
    let albums: [HomeAlbum]
    let isLoading: Bool
    let hasMore: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onSelect: (HomeAlbum) -> Void
    let onLoadMore: () -> Void
    let onRefresh: () async -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(
            top: 12, left: 16, bottom: 28, right: 16
        )

        let collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.backgroundView = nil
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(
            top: topInset, left: 0, bottom: bottomInset, right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        collectionView.keyboardDismissMode = .onDrag
        collectionView.register(
            AlbumGridCell.self,
            forCellWithReuseIdentifier: AlbumGridCell.reuseID
        )
        collectionView.delegate = context.coordinator

        let refresh = UIRefreshControl()
        refresh.tintColor = .systemMint
        refresh.addTarget(
            context.coordinator,
            action: #selector(Coordinator.refresh),
            for: .valueChanged
        )
        collectionView.refreshControl = refresh

        context.coordinator.collectionView = collectionView
        context.coordinator.configureDataSource(collectionView)
        context.coordinator.updateClosures(self)
        context.coordinator.apply(albums)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        let insets = UIEdgeInsets(
            top: topInset, left: 0, bottom: bottomInset, right: 0
        )
        if collectionView.contentInset != insets {
            collectionView.contentInset = insets
            collectionView.scrollIndicatorInsets = insets
        }
        context.coordinator.updateClosures(self)
        context.coordinator.isLoading = isLoading
        context.coordinator.hasMore = hasMore
        if !isLoading {
            context.coordinator.requestingMore = false
        }
        context.coordinator.apply(albums)
        if !isLoading {
            collectionView.refreshControl?.endRefreshing()
        }
    }

    final class Coordinator: NSObject, UICollectionViewDelegate,
        UICollectionViewDelegateFlowLayout {
        weak var collectionView: UICollectionView?
        private var dataSource: UICollectionViewDiffableDataSource<
            Int, HomeAlbum
        >!

        var albums: [HomeAlbum] = []
        var isLoading = false
        var hasMore = true
        var onSelect: (HomeAlbum) -> Void = { _ in }
        var onLoadMore: () -> Void = {}
        var onRefresh: () async -> Void = {}
        var requestingMore = false
        private var lastKey = ""

        func configureDataSource(_ collectionView: UICollectionView) {
            dataSource = UICollectionViewDiffableDataSource<Int, HomeAlbum>(
                collectionView: collectionView
            ) { collectionView, indexPath, album in
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: AlbumGridCell.reuseID,
                    for: indexPath
                ) as! AlbumGridCell
                cell.configure(with: album)
                return cell
            }
        }

        func updateClosures(_ view: CategoryGridView) {
            onSelect = view.onSelect
            onLoadMore = view.onLoadMore
            onRefresh = view.onRefresh
        }

        func apply(_ albums: [HomeAlbum]) {
            self.albums = albums
            let key = "\(albums.count)|\(albums.first?.aid ?? "")|\(albums.last?.aid ?? "")"
            guard key != lastKey else { return }
            lastKey = key

            var snapshot = NSDiffableDataSourceSnapshot<Int, HomeAlbum>()
            snapshot.appendSections([0])
            snapshot.appendItems(albums, toSection: 0)
            dataSource.apply(snapshot, animatingDifferences: false)

            DispatchQueue.main.async { [weak self] in
                self?.checkNeedsMore()
            }
        }

        private func requestMore() {
            guard !isLoading, hasMore, !requestingMore else { return }
            requestingMore = true
            onLoadMore()
        }

        private func checkNeedsMore() {
            guard let collectionView,
                  !isLoading,
                  hasMore else { return }
            let visibleHeight = collectionView.bounds.height
            guard visibleHeight > 0 else { return }
            if collectionView.contentSize.height < visibleHeight + 240 {
                requestMore()
            }
        }

        @objc func refresh() {
            Task { await onRefresh() }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isLoading, hasMore else { return }
            let remaining = scrollView.contentSize.height
                - scrollView.contentOffset.y
                - scrollView.bounds.height
            if remaining < 360 {
                requestMore()
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didSelectItemAt indexPath: IndexPath
        ) {
            guard albums.indices.contains(indexPath.item) else { return }
            onSelect(albums[indexPath.item])
            collectionView.deselectItem(at: indexPath, animated: false)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let available = collectionView.bounds.width - 32 - 20
            let width = max(1, available / 3)
            return CGSize(width: width, height: width * 4 / 3 + 52)
        }
    }
}

private final class AlbumGridCell: UICollectionViewCell {
    static let reuseID = "AlbumGridCell"

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private var task: Task<Void, Never>?
    private var album: HomeAlbum?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 10
        coverView.backgroundColor = .secondarySystemFill

        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail

        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .secondaryLabel
        metaLabel.numberOfLines = 1

        for view in [coverView, titleLabel, metaLabel] {
            view.translatesAutoresizingMaskIntoConstraints = true
            contentView.addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        let coverHeight = width * 4 / 3
        coverView.frame = CGRect(
            x: 0, y: 0, width: width, height: coverHeight
        )
        titleLabel.frame = CGRect(
            x: 0, y: coverHeight + 6, width: width, height: 30
        )
        metaLabel.frame = CGRect(
            x: 0, y: coverHeight + 38, width: width, height: 12
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        album = nil
        coverView.image = nil
        titleLabel.text = nil
        metaLabel.text = nil
    }

    func configure(with album: HomeAlbum) {
        self.album = album
        titleLabel.text = album.title
        var bits: [String] = []
        if let pages = album.pages {
            bits.append("\(pages)P")
        }
        if !album.date.isEmpty {
            bits.append(album.date)
        }
        metaLabel.text = bits.joined(separator: " · ")
        coverView.image = nil

        task?.cancel()
        guard let url = album.coverURL else { return }
        let aid = album.aid
        task = Task { @MainActor [weak self] in
            let image = await CoverImageStore.shared.image(
                for: url, referer: album.pageURL
            )
            guard !Task.isCancelled, self?.album?.aid == aid else { return }
            self?.coverView.image = image
        }
    }
}
