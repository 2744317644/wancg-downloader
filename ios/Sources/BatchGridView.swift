import SwiftUI
import UIKit
import Kingfisher

struct BatchGridView: UIViewRepresentable {
    let albums: [HomeAlbum]
    let isLoading: Bool
    let hasMore: Bool
    let datasetKey: String
    let reloadToken: Int
    let topInset: CGFloat
    let bottomInset: CGFloat
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
        collectionView.backgroundColor = .clear
        collectionView.isOpaque = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.contentInset = UIEdgeInsets(
            top: topInset, left: 0, bottom: bottomInset, right: 0
        )
        collectionView.scrollIndicatorInsets = collectionView.contentInset
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
        let insets = UIEdgeInsets(
            top: topInset, left: 0, bottom: bottomInset, right: 0
        )
        if collectionView.contentInset != insets {
            collectionView.contentInset = insets
            collectionView.scrollIndicatorInsets = insets
        }
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
                if !isLoading {
                    lastRequestedCount = -1
                }
                collectionView.collectionViewLayout.invalidateLayout()
                DispatchQueue.main.async { [weak self] in
                    self?.checkContentNeedsMore()
                }
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 10
        coverView.layer.cornerCurve = .continuous
        coverView.backgroundColor = UIColor.label.withAlphaComponent(0.05)
        coverView.kf.indicatorType = .none

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
        coverView.kf.cancelDownloadTask()
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
        coverView.kf.cancelDownloadTask()
        coverView.image = nil

        guard let url = album.coverURL else { return }
        let pageURL = album.pageURL.absoluteString
        let modifier = AnyModifier { request in
            var request = request
            request.setValue(pageURL, forHTTPHeaderField: "Referer")
            request.setValue(
                Self.userAgent, forHTTPHeaderField: "User-Agent"
            )
            return request
        }
        coverView.kf.setImage(
            with: url,
            options: [
                .processor(
                    DownsamplingImageProcessor(
                        size: CGSize(width: 360, height: 480)
                    )
                ),
                .scaleFactor(UIScreen.main.scale),
                .backgroundDecode,
                .requestModifier(modifier),
                .transition(.fade(0.15)),
            ]
        )
    }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) " +
        "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
        "Version/17.0 Mobile/15E148 Safari/604.1"
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
