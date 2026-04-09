import SwiftUI

/// Displayed when the widget has no items to show, either because
/// the user isn't signed in or there's nothing to watch.
struct WidgetEmptyStateView: View {
    let serverName: String?

    var body: some View {
        VStack {
            Image(systemName: "tv")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(serverName == nil ? "Sign in to Cove" : "Nothing to watch")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
