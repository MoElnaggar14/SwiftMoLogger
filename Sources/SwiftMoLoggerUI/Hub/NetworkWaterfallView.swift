#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger
#if canImport(UIKit) && (os(iOS) || os(visionOS))
import UIKit
#elseif canImport(AppKit) && os(macOS)
import AppKit
#endif

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
                HubEmptyState(systemImage: "network.slash", title: "No HTTP traffic in window")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events) { event in
                            row(event: event)
                                .onTapGesture { selected = event }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(spokenSummary(for: event))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityHint("Shows request details.")
                                .accessibilityAction { selected = event }
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
                Text("\(event.method) \(displayName(for: event))")
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer()
                Text("\(Int(event.durationSeconds * 1000))ms")
                    .font(.caption2.monospacedDigit())
                if isFailure(event) {
                    // Non-colour cue for failures, alongside the status code.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(color(for: event))
                }
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

    private func displayName(for event: NetworkEvent) -> String {
        event.url.lastPathComponent.isEmpty ? event.url.host ?? "?" : event.url.lastPathComponent
    }

    private func isFailure(_ event: NetworkEvent) -> Bool {
        event.errorDescription != nil || event.statusCode >= 400
    }

    /// Spoken row summary, e.g. "GET orders, status 200, 142 milliseconds".
    private func spokenSummary(for event: NetworkEvent) -> String {
        var parts = ["\(event.method) \(displayName(for: event))"]
        parts.append(event.statusCode > 0 ? "status \(event.statusCode)" : "no status")
        parts.append("\(Int(event.durationSeconds * 1000)) milliseconds")
        if let error = event.errorDescription {
            parts.append("failed: \(error)")
        } else if event.statusCode >= 400 {
            parts.append("failed")
        }
        return parts.joined(separator: ", ")
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
    @State private var copied = false

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("Method", value: event.method)
                LabeledContent("URL", value: event.url.absoluteString)
                LabeledContent("Body", value: "\(event.requestBytes)B")
            }
            if let headers = event.requestHeaders, !headers.isEmpty {
                Section("Request Headers") {
                    ForEach(headers.keys.sorted(), id: \.self) { name in
                        LabeledContent(name, value: headers[name] ?? "")
                    }
                }
            }
            if let requestBody = event.requestBody {
                bodySection("Request Body", captured: requestBody)
            }
            Section("Response") {
                LabeledContent("Status", value: "\(event.statusCode)")
                LabeledContent("Body", value: "\(event.responseBytes)B")
                LabeledContent("Duration", value: String(format: "%.1f ms", event.durationSeconds * 1000))
                if let err = event.errorDescription {
                    LabeledContent("Error", value: err)
                }
            }
            if let responseBody = event.responseBody {
                bodySection("Response Body", captured: responseBody)
            }
            Section("Timing") {
                LabeledContent("Started", value: event.startedAt.formatted())
                LabeledContent("Ended", value: event.endedAt.formatted())
            }
            Section("cURL") {
                Text(event.curlCommand)
                    .font(.caption.monospaced())
                    .hubSelectableText()
                if HubClipboard.isAvailable {
                    Button(copied ? "Copied" : "Copy as cURL") {
                        HubClipboard.copy(event.curlCommand)
                        copied = true
                    }
                    .accessibilityHint("Copies a curl command for this request. Secrets stay redacted.")
                }
            }
        }
        .navigationTitle("HTTP Exchange")
    }

    private func bodySection(_ title: String, captured: NetworkBody) -> some View {
        Section {
            Text(captured.text)
                .font(.caption.monospaced())
                .hubSelectableText()
        } header: {
            Text(title)
        } footer: {
            if captured.isTruncated {
                Text("Truncated at the capture limit.")
            }
        }
    }
}

/// Copies text where the platform has a pasteboard (iOS, Mac Catalyst,
/// visionOS and macOS). tvOS and watchOS have none.
enum HubClipboard {
    static var isAvailable: Bool {
        #if os(iOS) || os(visionOS) || os(macOS)
        return true
        #else
        return false
        #endif
    }

    @MainActor
    static func copy(_ string: String) {
        #if canImport(UIKit) && (os(iOS) || os(visionOS))
        UIPasteboard.general.string = string
        #elseif canImport(AppKit) && os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
private extension View {
    /// Lets the user select and copy text where SwiftUI supports it.
    @ViewBuilder
    func hubSelectableText() -> some View {
        #if os(tvOS) || os(watchOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}

/// Internal empty-state placeholder. Deliberately named with an underscore
/// prefix so it never shadows Apple's iOS 17 `ContentUnavailableView`.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
struct HubEmptyState: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
