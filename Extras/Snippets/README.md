# Xcode code snippets

Five snippets covering the calls you'll type most often.

| Prefix | Expands to |
|---|---|
| `smlinfo` | `logger.info(…, tag:, metadata:)` |
| `smlerror` | `logger.error(<#error#>, tag:, metadata:)` |
| `smlmeasure` | `signposter.measure("name", tag: .performance) { … }` |
| `smlcontext` | `LogContext.with(…) { … }` |
| `smlcrumb` | `breadcrumbs.record(…, category: .userAction)` |

## Install

```bash
cp Extras/Snippets/*.codesnippet ~/Library/Developer/Xcode/UserData/CodeSnippets/
```

Restart Xcode. The snippets show up in the Snippets Library (`⌘⇧L`) and are autocompleted by their prefix.

## Uninstall

```bash
rm ~/Library/Developer/Xcode/UserData/CodeSnippets/com.swiftmologger.*.codesnippet
```
