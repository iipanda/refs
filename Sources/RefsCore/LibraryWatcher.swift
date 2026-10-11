import Foundation
import Darwin

/// Observes committed sidecar changes, including writes from another process.
public final class LibraryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let root: URL
    private let onChange: () -> Void

    public init(root: URL, onChange: @escaping () -> Void) throws {
        self.root = root; self.onChange = onChange
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try start()
    }
    private func start() throws {
        let fd = open(root.path, O_EVTONLY)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let replaced = !(self.source?.data.intersection([.rename, .delete]).isEmpty ?? true)
            pending?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let source = self.source, replaced {
                    source.cancel()
                    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try? start()
                }
                onChange()
            }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: item)
        }
        self.source = source
        source.resume()
    }
    deinit { pending?.cancel(); source?.cancel() }
}
