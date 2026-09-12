import Foundation

/// A single transfer — as much of `URLSessionDownloadTask` as the engine uses.
///
/// Exists so `DownloadManagerService` can be driven by a stub in tests, the same
/// way `AudioPlayerBackend` lets `AudioPlaybackManager` be tested without a real
/// media pipeline. A background `URLSession` cannot be exercised from a unit test:
/// it needs a real network, real files, and delivers its callbacks on its own
/// schedule.
public protocol DownloadTaskHandle: AnyObject, Sendable {

    /// Identifies this task in the delegate callbacks.
    var taskIdentifier: Int { get }

    /// Free-form tag; the engine stores the `DownloadItem.id` here.
    var taskDescription: String? { get set }

    /// The URL the task was created with, used to reconcile live tasks against
    /// database rows after a relaunch.
    var originalURL: URL? { get }

    func resume()
    func cancel()

    /// Cancel, handing back resume data when the server supports ranged requests.
    func cancel(byProducingResumeData handler: @escaping @Sendable (Data?) -> Void)
}

/// The engine's view of `URLSession`.
public protocol DownloadSession: Sendable {
    func makeDownloadTask(request: URLRequest) -> any DownloadTaskHandle
    func makeDownloadTask(resumeData: Data) -> any DownloadTaskHandle

    /// Tasks the session still knows about, including ones that outlived the app.
    func activeTasks() async -> [any DownloadTaskHandle]
}

// MARK: - URLSession conformance

extension URLSessionDownloadTask: DownloadTaskHandle {
    public var originalURL: URL? { originalRequest?.url }
}

extension URLSession: DownloadSession {
    public func makeDownloadTask(request: URLRequest) -> any DownloadTaskHandle {
        downloadTask(with: request)
    }

    public func makeDownloadTask(resumeData: Data) -> any DownloadTaskHandle {
        downloadTask(withResumeData: resumeData)
    }

    public func activeTasks() async -> [any DownloadTaskHandle] {
        await allTasks.compactMap { $0 as? URLSessionDownloadTask }
    }
}
