import SwiftUI
import UIKit

struct BatchGridView: UIViewRepresentable {
    let albums: [HomeAlbum]
    let isLoading: Bool
    let hasMore: Bool
    let datasetKey: String
    let reloadToken: Int
    let onSelect: (HomeAlbum) -> Void
    let onLoadMore: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(
            top: 12, left: 16, bottom: 24, right: 16
        )

        let collectionView = UICollectionView(
            frame: .zero, collectionViewLayout: layout
        )
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.indicatorStyle = .default
        collectionView.register(
            AlbumGridCell.self,
            forCellWithReuseIdentifier: AlbumGridCell.reuseID
        )
        collectionView.register(
            LoadingFooterView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: LoadingFooterView.reuseID
        )
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        context.coordinator.collectionView = collectionView
        context.coordinator.apply(from: self)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        context.coordinator.apply(from: self)
    }

    static func dismantleUIView(
        _ uiView: UICollectionView,
        coordinator: Coordinator
    ) {
        coordinator.collectionView = nil
    }

    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegateFlowLayout, UIScrollViewDelegate {
        weak var collectionView: UICollectionView?
        var albums: [HomeAlbum] = []
        private var datasetKey = ""
        private var reloadToken = -1
        private var isLoading = false
        private var hasMore = true
        private var onSelect: (HomeAlbum) -> Void = { _ in }
        private var onLoadMore: () -> Void = {}
        private var lastRequestedCount = -1

        init(_ parent: BatchGridView) {
            super.init()
            apply(from: parent)
        }

        func apply(from parent: BatchGridView) {
            onSelect = parent.onSelect
            onLoadMore = parent.onLoadMore

            let previous = albums
            let reset = parent.datasetKey != datasetKey
                || parent.reloadToken != reloadToken
            datasetKey = parent.datasetKey
            reloadToken = parent.reloadToken
            albums = parent.albums
            if reset {
                lastRequestedCount = -1
            }
            let loadingChanged = isLoading != parent.isLoading
            isLoading = parent.isLoading
            hasMore = parent.hasMore

            guard let collectionView else { return }

            if reset || previous.isEmpty || albums.count < previous.count {
                collectionView.reloadData()
                collectionView.collectionViewLayout.invalidateLayout()
                DispatchQueue.main.async { [weak self] in
                    self?.checkContentNeedsMore()
                }
                return
            }

            if albums.count > previous.count {
                let isAppend = albums[previous.count - 1].aid == previous.last?.aid
                if isAppend {
                    let paths = (previous.count..<albums.count).map {
                        IndexPath(item: $0, section: 0)
                    }
                    UIView.performWithoutAnimation {
                        collectionView.performBatchUpdates {
                            collectionView.insertItems(at: paths)
                        } completion: { [weak self] _ in
                            self?.checkContentNeedsMore()
                        }
                    }
                } else {
                    collectionView.reloadData()
                    DispatchQueue.main.async { [weak self] in
                        self?.checkContentNeedsMore()
                    }
                }
            } else if albums.count == previous.count,
                      albums.last?.aid != previous.last?.aid {
                collectionView.reloadData()
                DispatchQueue.main.async { [weak self] in
                    self?.checkContentNeedsMore()
                }
            }

            if loadingChanged {
                collectionView.collectionViewLayout.invalidateLayout()
            }
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            1
        }

        func collectionView(
            _ collectionView: UICollectionView,
            numberOfItemsInSection section: Int
        ) -> Int {
            albums.count
        }

        func collectionView(
            _ collectionView: UICollectionView,
            cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: AlbumGridCell.reuseID,
                for: indexPath
            ) as! AlbumGridCell
            if albums.indices.contains(indexPath.item) {
                cell.configure(with: albums[indexPath.item])
            }
            return cell
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            let footer = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: LoadingFooterView.reuseID,
                for: indexPath
            ) as! LoadingFooterView
            footer.setAnimating(isLoading)
            return footer
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let width = max(
                1,
                (collectionView.bounds.width - 32 - 20) / 3
            )
            return CGSize(width: width, height: width * 4 / 3 + 50)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForFooterInSection section: Int
        ) -> CGSize {
            guard isLoading, hasMore else { return .zero }
            return CGSize(width: collectionView.bounds.width, height: 56)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didSelectItemAt indexPath: IndexPath
        ) {
            guard albums.indices.contains(indexPath.item) else { return }
            onSelect(albums[indexPath.item])
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard hasMore, !isLoading else { return }
            let remaining = scrollView.contentSize.height
                - scrollView.contentOffset.y
                - scrollView.bounds.height
            if remaining < 360 {
                requestMore()
            }
        }

        private func checkContentNeedsMore() {
            guard let collectionView, hasMore, !isLoading else { return }
            guard collectionView.bounds.height > 0,
                  collectionView.contentSize.height > 0 else {
                return
            }
            if collectionView.contentSize.height
                < collectionView.bounds.height + 240 {
                requestMore()
            }
        }

        private func requestMore() {
            guard lastRequestedCount != albums.count else { return }
            lastRequestedCount = albums.count
            onLoadMore()
        }

        func resetRequestGate() {
            lastRequestedCount = -1
        }
    }
}

private final class AlbumGridCell: UICollectionViewCell {
    static let reuseID = "AlbumGridCell"

    private let coverView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private var album: HomeAlbum?
    private var task: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 10
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = UIColor.label.withAlphaComponent(0.05)

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2

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
            x: 0, y: coverHeight + 36, width: width, height: 12
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
        if self.album?.aid == album.aid, coverView.image != nil {
            return
        }
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
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let image = await CoverImageStore.shared.image(
                for: url, referer: album.pageURL
            )
            guard !Task.isCancelled, self?.album?.aid == aid else { return }
            self?.coverView.image = image
        }
    }
}

private final class LoadingFooterView: UICollectionReusableView {
    static let reuseID = "LoadingFooterView"

    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.hidesWhenStopped = true
        label.text = "加载中…"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAnimating(_ animating: Bool) {
        animating ? spinner.startAnimating() : spinner.stopAnimating()
        label.isHidden = !animating
    }
}
