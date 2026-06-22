import Foundation
import CoreServices

/// Watches files for **external** changes — the heartbeat of the vibe-coding cockpit (an AI agent
/// rewriting `ROADMAP.md` while you read it).
///
/// Built on FSEvents rather than a `DispatchSource` on the file descriptor, because the app's own
/// atomic save (`String.write(atomically: true)`) writes a temp file and *renames* it over the
/// original — which kills an fd-based watcher (the fd points at the now-orphaned inode). FSEvents
/// watches by **path** and reports the change regardless of inode, so a single watcher survives any
/// number of agent rewrites. `kFSEventStreamCreateFlagFileEvents` gives per-file paths (recursively
/// for a directory), so the same primitive serves both the single open document and the whole
/// workspace tree. Callbacks are debounced (`latency`) by FSEvents and delivered on the main queue.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let latency: CFTimeInterval
    private let onChange: ([URL]) -> Void   // always invoked on the main queue

    private init(paths: [URL], latency: CFTimeInterval, onChange: @escaping ([URL]) -> Void) {
        self.latency = latency
        self.onChange = onChange
        start(paths: paths.map { $0.resolvingSymlinksInPath().path })
    }

    deinit { stop() }

    // MARK: - Factories

    /// Watch a single file by watching its parent directory and filtering to that file's path.
    /// Survives atomic-save renames; `onChange` fires only when *this* file changes on disk.
    static func file(_ url: URL, latency: CFTimeInterval = 0.15, onChange: @escaping () -> Void) -> FileWatcher {
        let target = url.resolvingSymlinksInPath().path
        let dir = url.deletingLastPathComponent()
        return FileWatcher(paths: [dir], latency: latency) { changed in
            if changed.contains(where: { $0.resolvingSymlinksInPath().path == target }) { onChange() }
        }
    }

    /// Watch an entire directory subtree (recursive), reporting the changed file URLs.
    static func tree(_ root: URL, latency: CFTimeInterval = 0.3, onChange: @escaping ([URL]) -> Void) -> FileWatcher {
        FileWatcher(paths: [root], latency: latency, onChange: onChange)
    }

    // MARK: - Lifecycle

    private func start(paths: [String]) {
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0,
                                           info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents
                           | kFSEventStreamCreateFlagUseCFTypes
                           | kFSEventStreamCreateFlagNoDefer)
        // Non-capturing C callback: pulls `self` back out of `info` and fires onChange. The stream is
        // scheduled on the MAIN queue (events are debounced by `latency`, so this won't spam main), so
        // the callback is serialized with deinit/stop — no use-after-free on the unretained pointer.
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info = info, count > 0 else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            watcher.onChange(paths.map { URL(fileURLWithPath: $0) })
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
