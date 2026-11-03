import SwiftUI
import UIKit
import QuartzCore

@MainActor
final class PerformanceMonitor: ObservableObject {
    @Published private(set) var fps = 0
    @Published private(set) var worstFrameMilliseconds = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frames = 0
    private var reportStart: CFTimeInterval = 0

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60, maximum: 120, preferred: 120
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        reportStart = CACurrentMediaTime()
        lastTimestamp = 0
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp > 0 {
            let delta = link.timestamp - lastTimestamp
            let milliseconds = Int(delta * 1000)
            if milliseconds > worstFrameMilliseconds {
                worstFrameMilliseconds = milliseconds
            }
        }
        lastTimestamp = link.timestamp
        frames += 1

        let elapsed = link.timestamp - reportStart
        if elapsed >= 1 {
            fps = Int(Double(frames) / elapsed)
            frames = 0
            reportStart = link.timestamp
        }
    }
}

struct PerformanceHUD: View {
    @StateObject private var monitor = PerformanceMonitor()

    var body: some View {
        HStack(spacing: 6) {
            Text("\(monitor.fps) FPS")
                .monospacedDigit()
            if monitor.worstFrameMilliseconds > 0 {
                Text("\(monitor.worstFrameMilliseconds)ms")
                    .foregroundStyle(
                        monitor.worstFrameMilliseconds > 24 ? .orange : .secondary
                    )
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        }
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}
