import AppKit
import Foundation

/// Where watchers look and what they can use. Tests point `home` at a temp folder.
public struct Environment: Sendable {
    public var home: URL
    public var now: @Sendable () -> Date
    public var store: Store
    public var scripts: ScriptRunner
    /// Names of running apps (used to ask only running browsers for tabs).
    public var runningApps: @Sendable () -> Set<String> = { [] }

    public init(home: URL, now: @escaping @Sendable () -> Date = { Date() }, store: Store, scripts: ScriptRunner) {
        self.home = home; self.now = now; self.store = store; self.scripts = scripts
    }

    public var desktop: URL { home.appendingPathComponent("Desktop", isDirectory: true) }
    public var trash: URL { home.appendingPathComponent(".Trash", isDirectory: true) }
    public var screenshotsRoot: URL { home.appendingPathComponent("Pictures/Screenshots", isDirectory: true) }

    /// `$SPAREHAND_HOME` if set (tests, manual checks), else the real home folder.
    public static var liveHome: URL {
        if let h = ProcessInfo.processInfo.environment["SPAREHAND_HOME"], !h.isEmpty { return URL(fileURLWithPath: h, isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Sparehand's own data folder under the (possibly overridden) home.
    public static var supportDirectory: URL {
        liveHome.appendingPathComponent("Library/Application Support/Sparehand", isDirectory: true)
    }

    public static func live(store: Store) -> Environment {
        var e = Environment(home: liveHome, store: store, scripts: OSAScriptRunner())
        e.runningApps = { Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName)) }
        return e
    }
}

/// Notices one kind of thing and proposes what to do about it.
public protocol Watcher: Sendable {
    var id: WatcherID { get }
    func candidates(_ env: Environment) async throws -> [Candidate]
}
