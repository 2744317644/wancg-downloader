import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WnacgWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DownloadLiveActivityWidget()
    }
}

struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.mint)
                    Text(context.attributes.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: context.state.progress)
                    .tint(.mint)

                Text(context.state.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.82))
            .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.mint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: context.state.progress)
                            .tint(.mint)
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.mint)
            } compactTrailing: {
                Text("\(Int(context.state.progress * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.mint)
            } minimal: {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.mint)
            }
        }
    }
}
