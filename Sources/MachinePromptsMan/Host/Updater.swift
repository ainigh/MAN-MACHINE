import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A release on GitHub, as much of it as the updater needs (tasks/11).
public struct Release: Equatable, Sendable {
    public var tag: String
    /// API URL of the zip asset (works for private repos through `gh api`).
    public var assetAPIURL: String
    /// Browser URL of the zip asset (public repos).
    public var assetDownloadURL: String

    public static let assetName = "MachinePromptsMan.zip"

    /// Parses `GET /repos/{owner}/{repo}/releases/latest`.
    public static func parse(_ data: Data) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let assets = obj["assets"] as? [[String: Any]],
              let zip = assets.first(where: { $0["name"] as? String == assetName }),
              let api = zip["url"] as? String, let dl = zip["browser_download_url"] as? String else { return nil }
        return Release(tag: tag, assetAPIURL: api, assetDownloadURL: dl)
    }
}

/// Version order for tags like "v0.0.12" or "v1.2.0-3-gabc" (git describe). Non-numeric parts compare as 0.
public enum Version {
    public static func components(_ v: String) -> [Int] {
        let core = v.drop { $0 == "v" || $0 == "V" }.split(separator: "-").first.map(String.init) ?? ""
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        guard !b.isEmpty, current != "dev" else { return false }   // a dev build never offers updates
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// Checks the latest release at launch and every 6 hours; downloads, swaps the bundle, relaunches
/// (tasks/11). Private repos go through `gh`, public ones through the API.
@MainActor
@Observable
public final class Updater {
    public static let repo = "ainigh/MAN-MACHINE"
    public static let interval: TimeInterval = 6 * 3600

    public private(set) var available: Release?
    public private(set) var lastError: String?
    public private(set) var installing = false
    public let currentVersion: String

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored public var log: ((String) -> Void)?
    /// Runs just before the process exits to relaunch. `exit` skips `applicationWillTerminate`, so the
    /// debounced snapshot and queued log lines are flushed here or lost.
    @ObservationIgnored public var beforeRelaunch: (() -> Void)?

    public init(currentVersion: String) { self.currentVersion = currentVersion }

    public func start() {
        Task { await check() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
    }

    public func check() async {
        do {
            let data = try await Self.latestReleaseJSON()
            guard let r = Release.parse(data) else { return }
            available = Version.isNewer(r.tag, than: currentVersion) ? r : nil
            lastError = nil
            if let a = available { log?("update available: \(a.tag)") }
        } catch {
            lastError = "\(error)"
            log?("update check failed: \(error)")
        }
    }

    static func latestReleaseJSON() async throws -> Data {
        if let gh = which("gh"),
           let out = try? await run(gh, ["api", "repos/\(repo)/releases/latest"]), !out.isEmpty {
            return out
        }
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: req)
        try requireOK(response)
        return data
    }

    /// An error page is not a release or a zip; without this a 404 body went on to `ditto`.
    static func requireOK(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
    }

    /// Downloads the zip, replaces the running bundle, and relaunches. The store lives in Application
    /// Support, outside the bundle, so it is untouched (tasks/11 acceptance).
    public func installAvailable() {
        guard let r = available, !installing else { return }
        installing = true
        let bundle = Bundle.main.bundleURL
        Task {
            do {
                try await Self.install(r, over: bundle)
                log?("updated to \(r.tag); relaunching")
                beforeRelaunch?()
                Self.relaunch(bundle)
            } catch {
                lastError = "\(error)"
                installing = false
                log?("update failed: \(error)")
            }
        }
    }

    static func install(_ r: Release, over bundle: URL) async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("mpm-update-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let zip = tmp.appendingPathComponent(Release.assetName)
        if let gh = which("gh"),
           let data = try? await run(gh, ["api", "-H", "Accept: application/octet-stream", r.assetAPIURL]), !data.isEmpty {
            try data.write(to: zip)
        } else {
            let (data, response) = try await URLSession.shared.data(from: URL(string: r.assetDownloadURL)!)
            try requireOK(response)
            try data.write(to: zip)
        }
        let unpacked = tmp.appendingPathComponent("unpacked")
        _ = try await run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        let newApp = unpacked.appendingPathComponent(bundle.lastPathComponent)
        guard fm.fileExists(atPath: newApp.path) else { throw CocoaError(.fileNoSuchFile) }
        // Swap: move the old bundle aside, put the new one in place, then drop the old one.
        let aside = bundle.deletingLastPathComponent().appendingPathComponent(".\(bundle.lastPathComponent).old")
        try? fm.removeItem(at: aside)
        try fm.moveItem(at: bundle, to: aside)
        do { try fm.moveItem(at: newApp, to: bundle) } catch {
            try? fm.moveItem(at: aside, to: bundle)
            throw error
        }
        try? fm.removeItem(at: aside)
    }

    static func relaunch(_ bundle: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", bundle.path]
        try? p.run()
        exit(0)
    }

    static func which(_ tool: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// Runs a tool and returns its stdout. Reads to EOF before waiting, so large output (a zip) cannot fill
    /// the pipe and stall the child.
    static func run(_ path: String, _ args: [String]) async throws -> Data {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
            return data
        }.value
    }
}
