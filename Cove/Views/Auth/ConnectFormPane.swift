import SwiftUI

/// Where the server details are actually entered.
///
/// One material card rather than a grouped `Form`, so it sits on the aurora
/// instead of covering it, and so the three fields read as a single task.
struct ConnectFormPane: View {
    let namespace: Namespace.ID
    @Binding var serverURL: String
    @Binding var username: String
    @Binding var password: String
    let isConnecting: Bool
    let errorMessage: String?
    let canConnect: Bool
    let onConnect: () -> Void
    let onBack: () -> Void

    /// Which field the keyboard is on, so Return can walk down the card.
    private enum Field { case server, username, password }
    @FocusState private var focused: Field?

    var body: some View {
        VStack(spacing: 24) {
            OnboardingWordmark(isCompact: true)
                .matchedGeometryEffect(id: "wordmark", in: namespace)

            VStack(spacing: 0) {
                field(
                    "Server", prompt: "jellyfin.example.com", text: $serverURL,
                    icon: "server.rack", field: .server, submit: .next
                )
                .textContentType(.URL)
                #if os(iOS)
                    .keyboardType(.URL)
                #endif

                Divider().padding(.leading, 46)

                field(
                    "Username", prompt: "Username", text: $username,
                    icon: "person", field: .username, submit: .next
                )
                .textContentType(.username)

                Divider().padding(.leading, 46)

                secureField(
                    "Password", text: $password, icon: "lock", field: .password
                )
            }
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.85), in: .rect(cornerRadius: 12))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button(action: onConnect) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView().tint(.white)
                    }
                    Text(isConnecting ? "Connecting…" : "Connect")
                        .bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isConnecting || !canConnect)

            Button("Back", systemImage: "chevron.left", action: onBack)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .disabled(isConnecting)
        }
        .padding(.horizontal, 28)
        .animation(.snappy, value: errorMessage)
        .onAppear { focused = .server }
    }

    // MARK: - Rows

    private func field(
        _ title: String, prompt: String, text: Binding<String>, icon: String,
        field: Field, submit: SubmitLabel
    ) -> some View {
        row(icon: icon) {
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(.white.opacity(0.4)))
                .focused($focused, equals: field)
                .submitLabel(submit)
                .onSubmit(advance)
                .autocorrectionDisabled()
                .disableAutocapitalization()
        }
    }

    private func secureField(
        _ title: String, text: Binding<String>, icon: String, field: Field
    ) -> some View {
        row(icon: icon) {
            SecureField(title, text: text, prompt: Text(title).foregroundStyle(.white.opacity(0.4)))
                .focused($focused, equals: field)
                .submitLabel(.go)
                .onSubmit(advance)
                .textContentType(.password)
        }
    }

    private func row(icon: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
                .foregroundStyle(.white)
                .tint(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    /// Return moves to the next empty field, and connects from the last one.
    private func advance() {
        switch focused {
        case .server: focused = .username
        case .username: focused = .password
        case .password, nil:
            focused = nil
            if canConnect { onConnect() }
        }
    }
}
