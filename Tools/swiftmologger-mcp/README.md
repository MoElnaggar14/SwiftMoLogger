# swiftmologger-mcp

An [MCP](https://modelcontextprotocol.io) server that lets AI coding agents (Claude Code, Codex, Cursor and others) read the **live logs of your debug build**, on a simulator or a real device, while you work:

```text
> Checkout just failed on my iPhone. Why?

⏺ swiftmologger.search_logs(min_level: "warning", since: "2m")
  #1843 14:02:11.482 ERROR [API] HTTP response {http.status=402, http.url=https://api.acme.com/v1/pay} NetworkLogger.swift:125
⏺ swiftmologger.get_entry(id: "…", context: 5)
  …the request, the 402, and the "Payment intent failed" error logged right after it
```

It runs on your Mac. It discovers every device running a SwiftMoLogger debug build with [`LiveSink`](../../README.md#2-bonjour-live-tail--zero-config-mac-companion) on the same network, keeps the most recent entries from each one, and answers the agent's questions.

## Tools

All tools are read-only.

| Tool | What it does |
| --- | --- |
| `list_devices` | Devices running LiveSink: app, version, connection state, buffered entries. |
| `search_logs` | Filter by device, level, tag, text (or `regex:`), time (`since: "5m"`) or sequence (`after_seq`). With no filters, it's a tail. |
| `get_entry` | One entry in full (metadata, source, thread), with the entries logged around it. |
| `wait_for` | Blocks until the next matching entry arrives, for example while you reproduce a bug. |
| `network_requests` | HTTP requests logged by `NetworkLogger`: method, redacted URL, status, duration and errors. |

## Set up the app

Debug builds only. See the main README:

```swift
#if DEBUG
let sink = LiveSink(statusLogger: logging.logger)
try sink.start()
logging.registry.addEngine(sink)
#endif
```

Add `NSLocalNetworkUsageDescription`, and `NSBonjourServices` containing `_swiftmologger._tcp`, to the Debug Info.plist. Both the app and the server must use SwiftMoLogger 4.0 or later, which speaks LiveSink protocol version 2.

## Install the server

Build it from a checkout of SwiftMoLogger (macOS 13+, Xcode 16.3+):

```bash
git clone https://github.com/MoElnaggar14/SwiftMoLogger
cd SwiftMoLogger/Tools/swiftmologger-mcp
swift build -c release
# The binary is .build/release/swiftmologger-mcp. Optionally copy it onto your PATH:
cp .build/release/swiftmologger-mcp /usr/local/bin/
```

**Claude Code**

```bash
claude mcp add swiftmologger -- /usr/local/bin/swiftmologger-mcp
```

**Codex** (`~/.codex/config.toml`)

```toml
[mcp_servers.swiftmologger]
command = "/usr/local/bin/swiftmologger-mcp"
tool_timeout_sec = 150   # wait_for can block for up to 120 s
```

**Cursor and others:** configure a stdio server whose command is the binary's path.

The first time the server browses, macOS may ask whether it can find devices on your local network. Allow it.

## Privacy

- **Redaction:** entries are redacted with SwiftMoLogger's default `Redactor` (emails, tokens, card numbers, …) before the agent sees them. Set `SWIFTMOLOGGER_MCP_REDACT=0` to turn this off, and only for logs you're happy to send to your AI provider.
- **App allowlist:** `SWIFTMOLOGGER_MCP_APPS=com.acme.shop,com.acme.shop.dev` accepts only those bundle identifiers.
- **Local only:** the server only talks to the agent over stdio and to devices on your network. LiveSink itself is unencrypted and unauthenticated, which is why it belongs in debug builds only.
- **Buffer size:** `SWIFTMOLOGGER_MCP_BUFFER` sets how many entries are kept per device (default 10 000).

## How it works

- **`SwiftMoLoggerMCPCore`** holds the domain:
  - the LiveSink line protocol (`WireLine`);
  - a ring buffer per device;
  - `LogQuery`;
  - the `DeviceHub` actor, which owns all state and the pending `wait_for` calls;
  - a Network.framework Bonjour client (`LiveSinkBrowser`) that reconnects with backoff.
- **`SwiftMoLoggerMCPServer`** maps MCP tool calls onto the hub, using the official [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (0.12.1).
- **This package lives under `Tools/`** so apps that depend on SwiftMoLogger never resolve the MCP SDK.

Run the tests with `swift test` in this directory.
