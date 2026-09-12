import SwiftUI

/// The app's first run: a welcome that says what Cove is, then the server details.
///
/// Two stages rather than one form, so nobody is asked for a URL before they know
/// what they are connecting to. The mark carries between them with
/// `matchedGeometryEffect`, which is why both panes share a namespace.
struct ServerConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    private enum Stage { case welcome, connect }
    @State private var stage: Stage = .welcome

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    /// Bumped on each failure so the haptic fires again on a repeated error.
    @State private var failureCount = 0

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var canConnect: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty && !username.isEmpty
    }

    var body: some View {
        ZStack {
            OnboardingBackground()

            switch stage {
            case .welcome:
                WelcomePane(namespace: namespace) {
                    withAnimation(transition) { stage = .connect }
                }
                .transition(.opacity)

            case .connect:
                ScrollView {
                    ConnectFormPane(
                        namespace: namespace,
                        serverURL: $serverURL,
                        username: $username,
                        password: $password,
                        isConnecting: isConnecting,
                        errorMessage: errorMessage,
                        canConnect: canConnect,
                        onConnect: { Task { await connect() } },
                        onBack: {
                            errorMessage = nil
                            withAnimation(transition) { stage = .welcome }
                        }
                    )
                    .padding(.vertical, 40)
                    // Centre in the visible area when it fits, scroll when the
                    // keyboard takes the bottom half.
                    .containerRelativeFrame(.vertical, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.error, trigger: failureCount)
        .sensoryFeedback(.success, trigger: appState.libraries.count)
    }

    private var transition: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.45)
    }

    // MARK: - Connecting

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        guard let url = Self.normalizedServerURL(from: serverURL) else {
            errorMessage = "That doesn't look like a server address."
            failureCount += 1
            return
        }

        do {
            try await authManager.connect(url: url, username: username, password: password)
            await appState.onConnected()
        } catch {
            errorMessage = error.localizedDescription
            failureCount += 1
        }
    }

    /// Accept what people actually type: bare hosts, stray whitespace, trailing
    /// slashes. Defaults to https, matching how servers are reachable in practice.
    static func normalizedServerURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
            text = "https://" + text
        }
        while text.hasSuffix("/") {
            text = String(text.dropLast())
        }

        guard let url = URL(string: text), let host = url.host(), !host.isEmpty else {
            return nil
        }
        return url
    }
}
