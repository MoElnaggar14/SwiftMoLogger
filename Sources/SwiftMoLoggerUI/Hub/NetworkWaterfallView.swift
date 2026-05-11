#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// HTTP exchanges drawn as a waterfall — start time on the X axis, one row
/// per request. Bar colour encodes status family.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct NetworkWaterfallView: View {
    @ObservedObject public var model: HubViewModel
    @State private var selected: NetworkEvent?

    public init(model: HubViewModel) { self.model = model }

    public var body: some View {
        let events = model.networkEvents.filter { model.inWindow($0.startedAt) || model.inWindow($0.endedAt) }
            .sorted { $0.startedAt < $1.startedAt }
        Group {
            if events.isEmpty {
                _HubEmptyState(systemImage: "network.slash", title: "No HTTP traffic in window")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events) { event in
                            row(event: event)
                                .onTapGesture { selected = event }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .sheet(item: $selected) { event in
            NavigationStack { NetworkEventDetailView(event: event) }
        }
    }

    @ViewBuilder
    private func row(event: NetworkEvent) -> some View {
        let totalSpan = max(model.windowDuration, 0.001)
        let startOffset = max(0, event.startedAt.timeIntervalSince(model.windowStart)) / totalSpan
        let duration = max(event.durationSeconds, 0) / totalSpan
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(event.method) \(event.url.lastPathComponent.isEmpty ? event.url.host ?? "?" : event.url.lastPathComponent)")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                Text("\(Int(event.durationSeconds * 1000))ms")
                    .font(.caption2.monospacedDigit())
                Text("\(event.statusCode)")
                    .font(.caption2.bold().monospacedDigit())
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(color(for: event).cornerRadius(3))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: geo.size.width, height: 8)
                    Rectangle()
                        .fill(color(for: event))
                        .frame(width: max(2, geo.size.width * CGFloat(duration)), height: 8)
                        .offset(x: geo.size.width * CGFloat(startOffset))
                }
            }
            .frame(height: 8)
        }
    }

    private func color(for event: NetworkEvent) -> Color {
        if event.errorDescription != nil { return .red }
        switch event.statusCode {
        case 200..<300: return .green
        case 300..<400: return .yellow
        case 400..<500: return .orange
        case 500..<600: return .red
        default: return .gray
        }
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct NetworkEventDetailView: View {
    let event: NetworkEvent

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("Method", value: event.method)
                LabeledContent("URL", value: event.url.absoluteString)
                LabeledContent("Body", value: "\(event.requestBytes)B")
            }
            Section("Response") {
                LabeledContent("Status", value: "\(event.statusCode)")
                LabeledContent("Body", value: "\(event.responseBytes)B")
                LabeledContent("Duration", value: String(format: "%.1f ms", event.durationSeconds * 1000))
                if let err = event.errorDescription {
                    LabeledContent("Error", value: err)
                }
            }
            Section("Timing") {
                LabeledContent("Started", value: event.startedAt.formatted())
                LabeledContent("Ended", value: event.endedAt.formatted())
            }
        }
        .navigationTitle("HTTP Exchange")
    }
}

/// Internal empty-state placeholder. Deliberately named with an underscore
/// prefix so it never shadows Apple's iOS 17 `ContentUnavailableView`.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct _HubEmptyState: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(title)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
