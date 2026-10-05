# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 4.x | ✅ |
| 3.x | ✅ latest 3.x release only |
| < 3.0 | ❌ |

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Report it privately through GitHub: go to the [Security tab](https://github.com/MoElnaggar14/SwiftMoLogger/security) and choose **Report a vulnerability** ([direct link](https://github.com/MoElnaggar14/SwiftMoLogger/security/advisories/new)). If that isn't available, contact the maintainer, [@MoElnaggar14](https://github.com/MoElnaggar14), privately using the details on their GitHub profile.

Please include:

- The version (or commit) and the products you use.
- What you found, and what an attacker could do with it.
- Steps or a small code sample that reproduces it.

What to expect:

- An acknowledgement within 3 working days.
- An assessment and a plan within 10 working days.
- A fix released as a patch version, with a GitHub security advisory crediting you (unless you'd rather stay anonymous).

## In scope

- Secrets or personal data reaching a log, breadcrumb, network event or the Flight Recorder file despite redaction being configured (`RedactingLogEngine`, `FlightRecorder(redactor:)`, `URLRedaction`, sensitive headers).
- `SystemLogger` exposing messages in release builds with `.private` or `.privateInRelease`.
- `LiveSink` or `WebSocketTailEngine` accepting connections or streaming in a way the docs don't describe (for example, starting in a release build without `allowInRelease: true`).
- Remote shippers sending data to an endpoint other than the one configured, or leaking credentials.
- Crashes or hangs an attacker can trigger with crafted input (for example, `traceparent` headers or log content).

## Out of scope

- `LiveSink` streaming unencrypted logs on the local network when you start it on purpose: that's documented, and it's why it's debug-only by default.
- Data your app chooses to log or ship. Redaction is opt-in; see the README.
