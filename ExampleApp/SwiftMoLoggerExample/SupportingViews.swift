// Supporting views from v2 are obsolete in v3 — replaced by the bundled
// `LogConsoleView` and `DiagnosticsHubView` from the `SwiftMoLoggerUI`
// product. This file is kept (rather than deleted) so the Xcode project's
// existing file references stay valid; remove it from the project once
// you regenerate the build phase.

import SwiftUI

struct LegacyPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Switch to the Console or Hub tab")
                .foregroundColor(.secondary)
        }
    }
}
