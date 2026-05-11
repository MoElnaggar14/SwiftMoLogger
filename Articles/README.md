# SwiftMoLogger — Article Series

A focused 5-part series on what shipped in v3 and why each piece exists.

| # | Title | What you'll learn |
|---|---|---|
| 1 | [Why I rewrote iOS logging from scratch](01-why-rewrite.md) | The shortcomings of `print` / `os.Logger` / SwiftyBeaver, and the design principles behind v3 |
| 2 | [Sub-µs logging: the performance design](02-performance.md) | Why the hot path is ~140 ns, locking choices, autoclosure tricks, allocation budgets |
| 3 | [Instruments in your app: building Diagnostics Hub](03-diagnostics-hub.md) | How the in-app timeline + waterfall + flame graph + vitals charts come together |
| 4 | [Zero-config debugging with Bonjour and Swift Macros](04-bonjour-and-macros.md) | The Mac CLI live tail, the macros target, and what they buy you in practice |
| 5 | [The production playbook: tracing, redaction, flight recorder](05-production-playbook.md) | The features that actually save you on the call you don't want to take at 3 AM |

Read in order, or jump to whichever is on fire for you today.
