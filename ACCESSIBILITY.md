# Accessibility

SwiftMoLogger is mostly a library with no UI. Its visible parts are developer tools: the SwiftUI log console and Diagnostics Hub (`SwiftMoLoggerUI`), and the `swiftmologger-inspector` Mac command-line tool. We want them to be usable by every developer, including people who use VoiceOver, larger text sizes or a colour-vision setting.

## Supported environments

- **SwiftUI views:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+. They use standard SwiftUI controls, lists and charts, so they get platform behaviour such as VoiceOver for controls, keyboard navigation on macOS, and Dark Mode.
- **Inspector CLI:** any terminal on macOS. The level is printed as text (`INFO`, `WARN`, `ERROR`), so the output doesn't rely on colour. Set `NO_COLOR=1` to turn colours off; they're also off when the output isn't a terminal. That helps with screen readers and braille displays.

## Known limitations

We haven't done a full accessibility audit of the Diagnostics Hub yet. Known gaps:

- The Hub's custom views (timeline scrubber, network waterfall, signpost flame graph, vitals charts) have no custom VoiceOver labels or values yet, so some bars and segments aren't described.
- A few labels use fixed font sizes, so they don't grow with Dynamic Type.
- Status in the waterfall and flame graph is shown mainly by colour.

## Reporting a barrier

If something in the package blocks you or your users, please [open an issue](https://github.com/MoElnaggar14/SwiftMoLogger/issues/new?template=bug_report.yml) and mention "accessibility" in the title. Tell us the platform, the assistive technology or setting you use, and what happened. Accessibility bugs are treated as bugs, not feature requests.
