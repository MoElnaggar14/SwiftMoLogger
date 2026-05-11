#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// In-app Instruments — one SwiftUI view that combines log tailing,
/// network waterfall, signpost flame graph, vitals charts, and breadcrumb
/// trail. A timeline scrubber at the top filters every sub-view to the
/// same window so you can rewind time on-device.
///
/// ```swift
/// import SwiftMoLoggerUI
///
/// struct DebugTab: View {
///     var body: some View { DiagnosticsHubView() }
/// }
/// ```
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct DiagnosticsHubView: View {
    @StateObject private var model: HubViewModel

    public init(model: HubViewModel? = nil) {
        _model = StateObject(wrappedValue: model ?? HubViewModel())
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TimelineScrubberView(model: model)
                .padding(.vertical, 8)
            Divider()
            tabs
            Divider()
            content
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "scope")
                .foregroundColor(.accentColor)
            Text("Diagnostics Hub")
                .font(.headline)
            Spacer()
            statBadge(systemImage: "text.alignleft", value: "\(model.entries.count)")
            statBadge(systemImage: "network", value: "\(model.networkEvents.count)")
            statBadge(systemImage: "waveform.path.ecg", value: "\(model.signpostEvents.count)")
            Button {
                model.clearAll()
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding(8)
    }

    private func statBadge(systemImage: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(value).font(.caption2.monospacedDigit())
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(4)
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(HubViewModel.Tab.allCases) { tab in
                    Button {
                        model.selectedTab = tab
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.selectedTab == tab ? Color.accentColor.opacity(0.18) : Color.clear)
                        .foregroundColor(model.selectedTab == tab ? .accentColor : .primary)
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedTab {
        case .logs:
            logsTab
        case .network:
            NetworkWaterfallView(model: model)
        case .signposts:
            SignpostFlameGraphView(model: model)
        case .vitals:
            VitalsChartsView(model: model)
        case .breadcrumbs:
            BreadcrumbsTrailView(model: model)
        }
    }

    private var logsTab: some View {
        let visible = model.entries.filter { model.inWindow($0.timestamp) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visible) { entry in
                    LogEntryRowView(entry: entry)
                        .padding(.horizontal, 8)
                    Divider()
                }
            }
        }
    }
}
#endif
