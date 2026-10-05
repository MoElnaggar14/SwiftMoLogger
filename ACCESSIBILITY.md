# Accessibility

SwiftMoLogger is mostly a library with no UI. Its visible parts are developer tools: the SwiftUI log console and Diagnostics Hub (`SwiftMoLoggerUI`), and the `swiftmologger-inspector` Mac command-line tool. We want them to be usable by every developer, including people who use VoiceOver, larger text sizes or a colour-vision setting.

## Supported environments

- **SwiftUI views:** iOS 16+, macOS 13+, tvOS 16+, watchOS 9+. They use standard SwiftUI controls, lists and charts, so they get platform behaviour such as VoiceOver for controls, keyboard navigation on macOS, and Dark Mode.
- **Inspector CLI:** any terminal on macOS. The level is printed as text (`INFO`, `WARN`, `ERROR`), so the output doesn't rely on colour. Set `NO_COLOR=1` to turn colours off; they're also off when the output isn't a terminal. That helps with screen readers and braille displays.

## What the Diagnostics Hub does for accessibility

- **VoiceOver descriptions.** Each network waterfall row is read as one element, for example "GET orders, status 200, 142 milliseconds", and includes the error for failed requests. Rows can be activated to open the request details. Each flame-graph span is read with its name, duration and start offset in the window. Vitals chart points have a time label and a value, and the timeline scrubber reads the current window (live or scrubbing, start and end time, number of log entries). Decorative shapes and placeholder icons are hidden from VoiceOver.
- **Adjustable timeline.** With VoiceOver, adjust the timeline (swipe up or down on iOS) to move the window by 30 seconds, the same step as the tvOS step buttons.
- **Dynamic Type.** All text and icons use text styles, so they grow with the user's text size.
- **Not only colour.** Failed requests in the waterfall show a warning symbol next to the status code, and slow spans (over 250 ms) in the flame graph show a warning symbol and are announced as "slow".

## Known limitations

We haven't done a full accessibility audit of the Diagnostics Hub yet, and the changes above have not yet been tested on device with VoiceOver on every platform. Known gaps:

- Bar lengths in the waterfall and flame graph and the timeline's density columns are only described in words as numbers (duration, offset, entry count); the relative shape of the graph isn't conveyed.
- Medium-duration (orange) flame-graph spans and 3xx/4xx/5xx status families are told apart by colour plus the status code text; there is no separate symbol per family.
- Some layouts use fixed heights (timeline density bar, waterfall rows, flame-graph lanes), so very large text sizes may be clipped there.

## Reporting a barrier

If something in the package blocks you or your users, please [open an issue](https://github.com/MoElnaggar14/SwiftMoLogger/issues/new?template=bug_report.yml) and mention "accessibility" in the title. Tell us the platform, the assistive technology or setting you use, and what happened. Accessibility bugs are treated as bugs, not feature requests.
