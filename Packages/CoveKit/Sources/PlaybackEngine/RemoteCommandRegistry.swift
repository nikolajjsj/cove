import MediaPlayer

/// Tracks the remote-command targets one component registered on the shared
/// `MPRemoteCommandCenter`, so it can remove exactly its own.
///
/// `MPRemoteCommand.removeTarget(nil)` removes *every* target on that command,
/// including ones registered by another component. With both an audio and a
/// video player in the app, whichever tears down last silently kills the
/// other's lock-screen controls.
@MainActor
final class RemoteCommandRegistry {

    private var registered: [(command: MPRemoteCommand, target: Any)] = []

    /// Enable `command` and attach `handler`, remembering the pair for removal.
    func register(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        registered.append((command, command.addTarget(handler: handler)))
    }

    /// Remove only the targets this registry added.
    func removeAll() {
        for (command, target) in registered {
            command.removeTarget(target)
        }
        registered.removeAll()
    }

    var isEmpty: Bool { registered.isEmpty }
}
