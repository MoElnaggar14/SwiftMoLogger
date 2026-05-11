#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

#if canImport(Charts)
import Charts
#endif

/// Memory / CPU / FPS / thermal line charts. Uses Swift Charts on iOS 16+
/// and falls back to a compact summary card on iOS 15.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct VitalsChartsView: View {
    @ObservedObject public var model: HubViewModel

    public init(model: HubViewModel) { self.model = model }

    public var body: some View {
        let ticks = model.vitalsHistory.filter { model.inWindow($0.timestamp) }
        Group {
            if ticks.isEmpty {
                placeholder
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                            charts(ticks: ticks)
                        } else {
                            summary(ticks: ticks)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("No vitals samples in window")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("AppVitalsMonitor.shared.start(interval: 1)")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *)
    @ViewBuilder
    private func charts(ticks: [VitalsTick]) -> some View {
        #if canImport(Charts)
        card(title: "Memory", value: latest("MB") { String(format: "%.0f", $0.memoryMB) }, ticks: ticks) {
            Chart(ticks) { tick in
                LineMark(x: .value("t", tick.timestamp), y: .value("MB", tick.memoryMB))
                    .foregroundStyle(.purple)
            }
        }
        card(title: "CPU", value: latest("%") { String(format: "%.1f", $0.cpuPercent) }, ticks: ticks) {
            Chart(ticks) { tick in
                LineMark(x: .value("t", tick.timestamp), y: .value("%", tick.cpuPercent))
                    .foregroundStyle(.orange)
            }
        }
        card(title: "FPS", value: latest("") { String(format: "%.0f", $0.fps) }, ticks: ticks) {
            Chart(ticks) { tick in
                LineMark(x: .value("t", tick.timestamp), y: .value("FPS", tick.fps))
                    .foregroundStyle(.green)
            }
        }
        #else
        summary(ticks: ticks)
        #endif
    }

    private func summary(ticks: [VitalsTick]) -> some View {
        let last = ticks.last
        return VStack(alignment: .leading, spacing: 8) {
            row("Memory", last.map { String(format: "%.0f MB", $0.memoryMB) } ?? "—")
            row("CPU", last.map { String(format: "%.1f %%", $0.cpuPercent) } ?? "—")
            row("FPS", last.map { String(format: "%.0f", $0.fps) } ?? "—")
            row("Thermal", last?.thermalState ?? "—")
            row("Battery", last.map { String(format: "%.0f %%", max($0.batteryLevel, 0) * 100) } ?? "—")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08).cornerRadius(8))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, value: String, ticks: [VitalsTick], @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(value).font(.title3.monospacedDigit().bold())
            }
            content()
                .frame(height: 100)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08).cornerRadius(8))
    }

    private func latest(_ unit: String, _ format: (VitalsTick) -> String) -> String {
        guard let tick = model.vitalsHistory.last else { return "—" }
        return "\(format(tick)) \(unit)".trimmingCharacters(in: .whitespaces)
    }
}
#endif
