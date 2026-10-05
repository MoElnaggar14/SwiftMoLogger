#if canImport(SwiftUI)
import SwiftUI
import SwiftMoLogger

/// In-app, drop-in log console. Subscribes to the live `LogEntry` stream and
/// renders entries with filtering, pause, clear, and copy-to-pasteboard.
///
/// ```swift
/// import SwiftMoLoggerUI
///
/// struct DebugRoot: View {
///     var body: some View { LogConsoleView() }
/// }
/// ```
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct LogConsoleView: View {
    @StateObject private var model: LogConsoleViewModel
    @State private var autoScroll = true

    public init(bufferLimit: Int = 2_000) {
        _model = StateObject(wrappedValue: LogConsoleViewModel(bufferLimit: bufferLimit))
    }

    public var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            entryList
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Level", selection: $model.minimumLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text("\(level.emoji) \(level.description)").tag(level)
                    }
                }
                .consolePickerStyle()

                Toggle(isOn: $model.isPaused) {
                    Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                }
                .consoleToggleStyle()

                Button {
                    model.clear()
                } label: {
                    Image(systemName: "trash")
                }

                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .consoleToggleStyle()
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter messages or tags", text: $model.filterText)
                    .consoleTextFieldStyle()
            }
        }
        .padding(8)
    }

    private var entryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visibleEntries) { entry in
                        LogEntryRowView(entry: entry)
                            .padding(.horizontal, 8)
                            .id(entry.id)
                        Divider()
                    }
                }
            }
            .onChange(of: model.entries.count) { _ in
                if autoScroll, let last = model.visibleEntries.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
#endif

// MARK: - Platform-adaptive styles
//
// Menu pickers, button toggles and rounded-border text fields don't exist on
// every platform the package supports; fall back to the system default there.

private extension View {
    @ViewBuilder
    func consolePickerStyle() -> some View {
        #if os(watchOS)
        self
        #elseif os(tvOS)
        if #available(tvOS 17.0, *) {
            pickerStyle(.menu)
        } else {
            self
        }
        #else
        pickerStyle(.menu)
        #endif
    }

    @ViewBuilder
    func consoleToggleStyle() -> some View {
        #if os(tvOS)
        self
        #else
        toggleStyle(.button)
        #endif
    }

    @ViewBuilder
    func consoleTextFieldStyle() -> some View {
        #if os(tvOS) || os(watchOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }
}
