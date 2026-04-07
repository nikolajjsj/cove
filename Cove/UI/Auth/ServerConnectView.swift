import SwiftUI

struct ServerConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)
                        Text("Cove")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Connect to your Jellyfin server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 20)
                }

                Section("Server") {
                    TextField(
                        "Server URL", text: $serverURL, prompt: Text("https://jellyfin.example.com")
                    )
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                }

                Section("Credentials") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isConnecting ? "Connecting..." : "Connect")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isConnecting || serverURL.isEmpty || username.isEmpty)
                }
            }
            .navigationTitle("Connect")
            .formStyle(.grouped)
        }
    }

    private func connect() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }

        // Normalize URL
        var urlString = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        // Remove trailing slash
        if urlString.hasSuffix("/") {
            urlString = String(urlString.dropLast())
        }

        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid server URL"
            return
        }

        do {
            try await authManager.connect(url: url, username: username, password: password)
            await appState.onConnected()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
