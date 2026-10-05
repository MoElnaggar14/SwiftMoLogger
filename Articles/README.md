# SwiftMoLogger — Article Series

A focused five-part series on how SwiftMoLogger 4.0 is designed, and why each piece exists. Every code sample uses the 4.0 API: one `LogEnvironment` built at your composition root and injected, with no singletons.

| # | Title | What you'll learn |
|---|---|---|
| 1 | [Why I rewrote iOS logging from scratch](01-why-rewrite.md) | Where `print`, `os.Logger` and classic loggers fall short, and the principles behind 4.0: injection over globals, structured entries, privacy by default |
| 2 | [Sub-µs logging: the performance design](02-performance.md) | How the hot path stays fast: locking, autoclosures, allocation budget and engine fan-out |
| 3 | [Instruments in your app: building the Diagnostics Hub](03-diagnostics-hub.md) | How the logs timeline, network waterfall, signpost flame graph and vitals charts come together |
| 4 | [Zero-config debugging with Bonjour and Swift Macros](04-bonjour-and-macros.md) | The Mac live tail, keeping it out of release builds, and what the macros do at the call site |
| 5 | [The production playbook: tracing, redaction, flight recorder](05-production-playbook.md) | The features that save you on the call you don't want to take at 3 AM |

Read in order, or jump to whichever is on fire for you today.

New to the package? Start with the [README](../README.md). Upgrading from 3.x? See [MIGRATION.md](../MIGRATION.md).
