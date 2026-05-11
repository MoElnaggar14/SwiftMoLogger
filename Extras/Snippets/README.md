# Xcode code snippets

Five snippets covering the calls you'll type most often.

| Prefix | Expands to |
|---|---|
| `smlinfo` | `SwiftMoLogger.info(…, tag:, metadata:)` |
| `smlerror` | `SwiftMoLogger.error(error:, tag:, metadata:)` |
| `smlmeasure` | `LogSignpost.measure("name", tag: .performance) { … }` |
| `smlcontext` | `SwiftMoLogger.withContext(…) { … }` |
| `smlcrumb` | `SwiftMoLogger.breadcrumb(…, category: .userAction)` |

## Install

```bash
cp Extras/Snippets/*.codesnippet ~/Library/Developer/Xcode/UserData/CodeSnippets/
```

Restart Xcode. The snippets show up in the Snippets Library (`⌘⇧L`) and are autocompleted by their prefix.

## Uninstall

```bash
rm ~/Library/Developer/Xcode/UserData/CodeSnippets/com.swiftmologger.*.codesnippet
```
