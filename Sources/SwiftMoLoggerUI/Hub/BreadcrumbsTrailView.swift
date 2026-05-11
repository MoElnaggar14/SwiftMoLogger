#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// Vertical timeline of recent ``Breadcrumb``s. Synced to the hub window.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct BreadcrumbsTrailView: View {
    @ObservedObject public var model: HubViewModel

    public init(model: HubViewModel) { self.model = model }

    public var body: some View {
        let crumbs = model.breadcrumbs.filter { model.inWindow($0.timestamp) }
        Group {
            if crumbs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fossil.shell").font(.system(size: 32)).foregroundColor(.secondary)
                    Text("No breadcrumbs in window").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(color(for: crumb.category))
                                        .frame(width: 10, height: 10)
                                    if index < crumbs.count - 1 {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.3))
                                            .frame(width: 1)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(crumb.category.rawValue)
                                            .font(.caption2.bold())
                                            .foregroundColor(color(for: crumb.category))
                                        Spacer()
                                        Text(formatTime(crumb.timestamp))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                    Text(crumb.message)
                                        .font(.callout)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if !crumb.metadata.isEmpty {
                                        Text(crumb.metadata.storage.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                                            .font(.caption2.monospaced())
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.bottom, 12)
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func color(for category: Breadcrumb.Category) -> Color {
        switch category {
        case .userAction: return .blue
        case .navigation: return .teal
        case .network: return .green
        case .lifecycle: return .orange
        case .state: return .purple
        case .custom: return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
#endif
