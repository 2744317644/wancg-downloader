import SwiftUI
import UIKit

/// Detects a second tap on the already-selected tab. SwiftUI's TabView does
/// not expose this event, so we forward the underlying UITabBarController
/// delegate and report same-tab selections.
struct TabBarReselectObserver: UIViewControllerRepresentable {
    let onReselect: (Int) -> Void
    let onSelect: (Int) -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onReselect = onReselect
        controller.onSelect = onSelect
        return controller
    }

    func updateUIViewController(
        _ uiViewController: ObserverController,
        context: Context
    ) {
        uiViewController.onReselect = onReselect
        uiViewController.onSelect = onSelect
    }

    final class ObserverController: UIViewController {
        var onReselect: ((Int) -> Void)?
        var onSelect: ((Int) -> Void)?
        private var proxy: TabBarDelegateProxy?
        private var attempts = 0

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installDelegate()
        }

        private func installDelegate() {
            guard let tabBarController = findTabBarController() else {
                attempts += 1
                if attempts < 10 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        [weak self] in
                        self?.installDelegate()
                    }
                }
                return
            }

            if let proxy,
               tabBarController.delegate === proxy {
                return
            }

            let proxy = TabBarDelegateProxy(
                original: tabBarController.delegate,
                onReselect: { [weak self] index in
                    self?.onReselect?(index)
                },
                onSelect: { [weak self] index in
                    self?.onSelect?(index)
                }
            )
            tabBarController.delegate = proxy
            self.proxy = proxy
        }

        private func findTabBarController() -> UITabBarController? {
            var controller: UIViewController? = self
            while let current = controller {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                controller = current.parent
            }

            guard let root = view.window?.rootViewController else {
                return nil
            }
            return Self.findTabBarController(in: root)
        }

        private static func findTabBarController(
            in controller: UIViewController
        ) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }
            for child in controller.children {
                if let tabBarController = findTabBarController(in: child) {
                    return tabBarController
                }
            }
            if let presented = controller.presentedViewController {
                return findTabBarController(in: presented)
            }
            return nil
        }
    }
}

private final class TabBarDelegateProxy: NSObject,
    UITabBarControllerDelegate {
    weak var original: (any UITabBarControllerDelegate)?
    private let onReselect: (Int) -> Void
    private let onSelect: (Int) -> Void

    init(
        original: (any UITabBarControllerDelegate)?,
        onReselect: @escaping (Int) -> Void,
        onSelect: @escaping (Int) -> Void
    ) {
        self.original = original
        self.onReselect = onReselect
        self.onSelect = onSelect
        super.init()
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        shouldSelect viewController: UIViewController
    ) -> Bool {
        if let index = tabBarController.viewControllers?
            .firstIndex(where: { $0 === viewController }),
           tabBarController.selectedIndex == index {
            onReselect(index)
        }
        return original?.tabBarController?(
            tabBarController,
            shouldSelect: viewController
        ) ?? true
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        didSelect viewController: UIViewController
    ) {
        if let index = tabBarController.viewControllers?
            .firstIndex(where: { $0 === viewController }) {
            onSelect(index)
        }
        original?.tabBarController?(
            tabBarController,
            didSelect: viewController
        )
    }
}
