#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// Single-row rendering of a ``LogEntry``. Designed for `LazyVStack` /
/// `List` use; keeps layout cost minimal by avoiding per-entry formatters.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct LogEntryRowView: View {
    public let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    public init(entry: LogEntry) {
        self.entry = entry
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.emoji)
                .font(.system(size: 14))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Self.timeFormatter.string(from: entry.timestamp))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(entry.level.description)
                        .font(.system(.caption2, design: .monospaced).bold())
                        .foregroundColor(color(for: entry.level))
                    if let tag = entry.tag {
                        Text(tag.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    Spacer(minLength: 0)
                    Text(entry.threadName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(entry.message)
                    .font(.system(.callout, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.metadata.isEmpty {
                    Text(metadataText)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text("\(entry.source.fileName):\(entry.source.line)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }

    private var metadataText: String {
        entry.metadata.storage
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: " ")
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .trace, .debug: return .secondary
        case .info: return .blue
        case .notice: return .teal
        case .warning: return .orange
        case .error: return .red
        case .critical, .fault: return .pink
        }
    }
}
#endif
