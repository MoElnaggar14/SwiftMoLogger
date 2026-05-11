#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// Activity density bar + slider scrubber. Renders one column per second
/// of the displayed window, height proportional to the count of log
/// entries falling in that bucket.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct TimelineScrubberView: View {
    @ObservedObject public var model: HubViewModel

    public init(model: HubViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeLabel(model.windowStart))
                    .font(.caption2.monospacedDigit())
                Spacer()
                if model.scrubbedTime != nil {
                    Text("SCRUBBING")
                        .font(.caption2.bold())
                        .foregroundColor(.orange)
                    Button("Live") { model.scrubbedTime = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
                Spacer()
                Text(timeLabel(model.windowEnd))
                    .font(.caption2.monospacedDigit())
            }
            density
                .frame(height: 32)
            slider
        }
        .padding(.horizontal, 8)
    }

    private var density: some View {
        GeometryReader { geo in
            let bucketCount = max(Int(model.windowDuration), 1)
            let bucketSeconds: TimeInterval = model.windowDuration / Double(bucketCount)
            let width = geo.size.width / CGFloat(bucketCount)
            let buckets = densityBuckets(count: bucketCount, bucketSeconds: bucketSeconds)
            let maxValue = max(buckets.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { index, value in
                    Rectangle()
                        .fill(barColor(forCount: value))
                        .frame(width: max(width - 1, 1), height: max(2, CGFloat(value) / CGFloat(maxValue) * geo.size.height))
                }
            }
        }
    }

    private var slider: some View {
        let now = Date()
        let span: TimeInterval = 600
        let lowerBound = now.addingTimeInterval(-span)
        let binding = Binding<Double>(
            get: {
                let target = model.scrubbedTime ?? now
                return target.timeIntervalSince(lowerBound)
            },
            set: { newValue in
                let date = lowerBound.addingTimeInterval(newValue)
                model.scrubbedTime = date.timeIntervalSinceNow > -2 ? nil : date
            }
        )
        return Slider(value: binding, in: 0...span)
            .controlSize(.small)
    }

    private func densityBuckets(count: Int, bucketSeconds: TimeInterval) -> [Int] {
        let start = model.windowStart
        var buckets = Array(repeating: 0, count: count)
        for entry in model.entries {
            let offset = entry.timestamp.timeIntervalSince(start)
            guard offset >= 0, offset <= model.windowDuration else { continue }
            let index = min(count - 1, max(0, Int(offset / bucketSeconds)))
            buckets[index] += 1
        }
        return buckets
    }

    private func barColor(forCount count: Int) -> Color {
        if count == 0 { return .secondary.opacity(0.15) }
        return Color.accentColor.opacity(min(1.0, 0.25 + Double(count) / 20))
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
#endif
