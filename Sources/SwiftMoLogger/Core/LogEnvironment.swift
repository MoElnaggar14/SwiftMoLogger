import Foundation

/// Everything one logging setup owns: the engine registry, a logger bound to
/// it, a live stream, and the diagnostics stores the Hub, Flight Recorder and
/// bug reporter read from.
///
/// SwiftMoLogger has no singletons. Create a `LogEnvironment` once at your
/// composition root (the `App` initializer, the app delegate, a DI container)
/// and inject it, or just the piece a component needs:
///
/// ```swift
/// @main
/// struct ShopApp: App {
///     private let logging = LogEnvironment()
///
///     init() {
///         logging.registry.addEngine(MemoryLogEngine())
///     }
///
///     var body: some Scene {
///         WindowGroup {
///             RootView(checkout: CheckoutService(log: logging.logger))
///         }
///     }
/// }
/// ```
///
/// Prefer passing the narrowest dependency: a service needs a ``MoLogger``,
/// not the whole environment.
public struct LogEnvironment: Sendable {
    public let registry: EngineRegistry
    /// A logger bound to ``registry``. Derive tagged children with ``MoLogger/with(tag:)``.
    public let logger: MoLogger
    /// Live `AsyncStream` of every entry, already registered with ``registry``.
    public let stream: LogStream
    public let breadcrumbs: BreadcrumbStore
    public let networkEvents: NetworkEventStore
    public let signposts: SignpostEventStore
    public let vitals: VitalsHistoryStore

    /// Creates a fresh, independent environment. Every argument can be
    /// replaced, e.g. to share stores between environments or to inject fakes.
    public init(
        registry: EngineRegistry = EngineRegistry(),
        breadcrumbs: BreadcrumbStore = BreadcrumbStore(),
        networkEvents: NetworkEventStore = NetworkEventStore(),
        signposts: SignpostEventStore = SignpostEventStore(),
        vitals: VitalsHistoryStore = VitalsHistoryStore()
    ) {
        self.registry = registry
        self.logger = MoLogger(registry: registry)
        self.stream = LogStream()
        self.breadcrumbs = breadcrumbs
        self.networkEvents = networkEvents
        self.signposts = signposts
        self.vitals = vitals
        registry.addEngine(stream)
    }

    /// Measures spans, logging through ``logger`` and recording into ``signposts``.
    public var signposter: Signposter {
        Signposter(logger: logger, store: signposts)
    }
}
