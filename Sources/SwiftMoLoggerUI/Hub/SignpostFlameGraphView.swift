#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// Signpost spans laid out as a flame graph. Spans that overlap in time
/// stack vertically; the duration controls horizontal width.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct SignpostFlameGraphView: View {
    @ObservedObject public var model: HubViewModel

    public init(model: HubViewModel) { self.model = model }

    public var body: some View {
        let spans = model.signpostEvents.filter {
            model.inWindow($0.startedAt) || model.inWindow($0.endedAt)
        }
        let layout = laneAssignments(for: spans)
        let lanes = (layout.values.max() ?? 0) + 1

        Group {
            if spans.isEmpty {
                placeholder
            } else {
                ScrollView(.vertical) {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            backgroundGrid(width: geo.size.width)
                            ForEach(spans) { span in
                                spanRect(span: span, lane: layout[span.id] ?? 0, totalWidth: geo.size.width)
                            }
                        }
                        .frame(width: geo.size.width, height: CGFloat(lanes) * 24)
                    }
                    .frame(minHeight: CGFloat(lanes) * 24 + 16)
                    .padding(8)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No signposts in window")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Wrap code in LogSignpost.measure(\"name\") { … }")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func backgroundGrid(width: CGFloat) -> some View {
        let ticks = 4
        return HStack(spacing: 0) {
            ForEach(0..<ticks, id: \.self) { _ in
                Rectangle()
                    .fill(Color.secondary.opacity(0.06))
                    .overlay(
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 0.5),
                        alignment: .trailing
                    )
            }
        }
        .frame(width: width)
    }

    private func spanRect(span: SignpostEvent, lane: Int, totalWidth: CGFloat) -> some View {
        let totalSpan = max(model.windowDuration, 0.001)
        let startOffset = max(0, span.startedAt.timeIntervalSince(model.windowStart)) / totalSpan
        let duration = max(span.durationSeconds, 0.0005) / totalSpan
        let width = max(6, totalWidth * CGFloat(duration))
        return HStack(spacing: 4) {
            Text(span.name)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .foregroundColor(.white)
            Text("\(Int(span.durationSeconds * 1000))ms")
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: 20)
        .background(color(for: span).cornerRadius(3))
        .offset(x: totalWidth * CGFloat(startOffset), y: CGFloat(lane) * 24)
    }

    private func color(for span: SignpostEvent) -> Color {
        let duration = span.durationSeconds
        if duration > 0.25 { return .red }
        if duration > 0.05 { return .orange }
        return .blue
    }

    /// Greedy lane assignment: place each span in the lowest-numbered lane
    /// whose current occupant has already ended.
    private func laneAssignments(for events: [SignpostEvent]) -> [UUID: Int] {
        var laneEnds: [Date] = []
        var result: [UUID: Int] = [:]
        let sorted = events.sorted { $0.startedAt < $1.startedAt }
        for event in sorted {
            var assignedLane: Int?
            for (index, end) in laneEnds.enumerated() where end <= event.startedAt {
                assignedLane = index
                break
            }
            if let lane = assignedLane {
                laneEnds[lane] = event.endedAt
                result[event.id] = lane
            } else {
                laneEnds.append(event.endedAt)
                result[event.id] = laneEnds.count - 1
            }
        }
        return result
    }
}
#endif
