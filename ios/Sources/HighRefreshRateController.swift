import UIKit
import QuartzCore

@MainActor
final class HighRefreshRateController: NSObject {
    static let shared = HighRefreshRateController()
    static let enabledKey = "display.force120"

    private var displayLink: CADisplayLink?

    private override init() {
        super.init()
    }

    func applySavedSetting() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.enabledKey) == nil {
            defaults.set(true, forKey: Self.enabledKey)
        }
        setEnabled(defaults.bool(forKey: Self.enabledKey))
    }

    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        value ? start() : stop()
    }

    private func start() {
        guard displayLink == nil else { return }
        guard UIScreen.main.maximumFramesPerSecond >= 120 else { return }

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 120, maximum: 120, preferred: 120
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        // Keeping an active 120Hz display link requests the ProMotion
        // frame budget; the actual render rate still follows the system.
    }
}
