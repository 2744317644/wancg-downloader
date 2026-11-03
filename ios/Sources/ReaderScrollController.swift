import SwiftUI
import UIKit

@MainActor
final class ReaderScrollController: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isScrollable = false
    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var viewportHeight: CGFloat = 0

    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []

    func attach(_ scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else {
            update()
            return
        }
        observations.removeAll()
        self.scrollView = scrollView
        observations = [
            scrollView.observe(\.contentOffset, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor in self?.update() }
            },
            scrollView.observe(\.contentSize, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor in self?.update() }
            },
            scrollView.observe(\.bounds, options: [.new]) {
                [weak self] _, _ in
                Task { @MainActor in self?.update() }
            },
        ]
        update()
    }

    func seek(to fraction: Double) {
        guard let scrollView else { return }
        let top = scrollView.adjustedContentInset.top
        let bottom = scrollView.adjustedContentInset.bottom
        let maxOffset = scrollView.contentSize.height
            + top + bottom
            - scrollView.bounds.height
        guard maxOffset > 1 else { return }
        let clamped = min(1, max(0, fraction))
        let y = -top + CGFloat(clamped) * maxOffset
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: y),
            animated: false
        )
        update()
    }

    private func update() {
        guard let scrollView else { return }
        let top = scrollView.adjustedContentInset.top
        let bottom = scrollView.adjustedContentInset.bottom
        contentHeight = scrollView.contentSize.height
        viewportHeight = scrollView.bounds.height
        let maxOffset = scrollView.contentSize.height
            + top + bottom
            - scrollView.bounds.height
        isScrollable = maxOffset > 1
        guard maxOffset > 1 else {
            progress = 0
            return
        }
        let value = (scrollView.contentOffset.y + top) / maxOffset
        progress = min(1, max(0, Double(value)))
    }
}

struct ReaderScrollObserver: UIViewRepresentable {
    let controller: ReaderScrollController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        attach(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        attach(from: uiView)
    }

    private func attach(from view: UIView, attempts: Int = 0) {
        var candidate: UIView? = view
        while let current = candidate {
            if let scrollView = current as? UIScrollView {
                controller.attach(scrollView)
                return
            }
            candidate = current.superview
        }
        guard attempts < 8 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            attach(from: view, attempts: attempts + 1)
        }
    }
}
