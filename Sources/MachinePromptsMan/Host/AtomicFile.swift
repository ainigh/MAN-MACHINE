import Foundation

/// Whole-file writes that leave either the old or the new contents on disk, never a torn file:
/// write a sibling temp file, fsync it, then `rename(2)`, which is atomic within one directory.
enum AtomicFile {
    static let tempSuffix = ".tmp"

    /// `beforeRename` exists so tests can simulate a crash between the temp write and the rename.
    static func write(_ data: Data, to url: URL, beforeRename: (() throws -> Void)? = nil) throws {
        let dir = url.deletingLastPathComponent()
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)\(tempSuffix)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        let handle = try FileHandle(forWritingTo: tmp)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
        try beforeRename?()
        guard rename(tmp.path, url.path) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    /// Temp files left behind by a crash before rename. They are never the authoritative copy.
    static func leftovers(in dir: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix(".") && $0.hasSuffix(tempSuffix) }.map { dir.appendingPathComponent($0) }
    }
}
