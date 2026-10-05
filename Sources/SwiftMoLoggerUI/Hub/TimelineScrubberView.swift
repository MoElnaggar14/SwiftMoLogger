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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Timeline window")
                .accessibilityValue(windowDescription)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: step(by: Self.stepSeconds)
                    case .decrement: step(by: -Self.stepSeconds)
                    @unknown default: break
                    }
                }
            slider
        }
        .padding(.horizontal, 8)
    }

    /// How far one step (tvOS button or VoiceOver swipe) moves the window.
    private static let stepSeconds: TimeInterval = 30
    /// How far back the scrubber reaches.
    private static let scrubSpan: TimeInterval = 600

    /// Spoken description of the visible window, e.g. "Live, 12:00:00 to 12:01:00, 42 log entries".
    private var windowDescription: String {
        let mode = model.scrubbedTime == nil ? "Live" : "Scrubbing"
        let count = model.entries.filter { model.inWindow($0.timestamp) }.count
        let noun = count == 1 ? "log entry" : "log entries"
        return "\(mode), \(timeLabel(model.windowStart)) to \(timeLabel(model.windowEnd)), \(count) \(noun)"
    }

    private var sliderValue: String {
        guard let scrubbed = model.scrubbedTime else { return "Live" }
        return "Window ends at \(timeLabel(scrubbed))"
    }

    /// Moves the window end by `delta` seconds, clamped to the scrub span.
    /// Returns to live when it reaches the present.
    private func step(by delta: TimeInterval) {
        let now = Date()
        let lowerBound = now.addingTimeInterval(-Self.scrubSpan)
        let current = (model.scrubbedTime ?? now).timeIntervalSince(lowerBound)
        let date = lowerBound.addingTimeInterval(min(Self.scrubSpan, max(0, current + delta)))
        model.scrubbedTime = date.timeIntervalSinceNow > -2 ? nil : date
    }

    private var density: some View {
        GeometryReader { geo in
            let bucketCount = max(Int(model.windowDuration), 1)
            let bucketSeconds: TimeInterval = model.windowDuration / Double(bucketCount)
            let width = geo.size.width / CGFloat(bucketCount)
            let buckets = densityBuckets(count: bucketCount, bucketSeconds: bucketSeconds)
            let maxValue = max(buckets.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, value in
                    Rectangle()
                        .fill(barColor(forCount: value))
                        .frame(
                            width: max(width - 1, 1),
                            height: max(2, CGFloat(value) / CGFloat(maxValue) * geo.size.height)
                        )
                }
            }
        }
    }

    private var slider: some View {
        let now = Date()
        let span = Self.scrubSpan
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
        #if os(tvOS)
        // tvOS has no Slider; step through the window with focusable buttons.
        let step = Self.stepSeconds
        return HStack {
            Button("−\(Int(step))s") { binding.wrappedValue = max(0, binding.wrappedValue - step) }
                .accessibilityLabel("Back \(Int(step)) seconds")
            Button("Live") { model.scrubbedTime = nil }
            Button("+\(Int(step))s") { binding.wrappedValue = min(span, binding.wrappedValue + step) }
                .accessibilityLabel("Forward \(Int(step)) seconds")
        }
        #else
        return Slider(value: binding, in: 0...span)
            .controlSize(.small)
            .accessibilityLabel("Scrub time")
            .accessibilityValue(sliderValue)
        #endif
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
