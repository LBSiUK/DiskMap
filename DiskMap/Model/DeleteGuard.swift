import Foundation

/// Decides whether an item may be moved to the Trash or deleted.
enum DeleteGuard {
    /// The data volume is mounted here and its folders also appear at the top level,
    /// so "/System/Volumes/Data/Users" and "/Users" are the same folder.
    static let dataVolumePrefix = "/System/Volumes/Data"

    static let protectedPaths: Set<String> = [
        "/", "/System", "/Library", "/Applications", "/Users", "/private",
        "/usr", "/bin", "/sbin", "/opt", "/Volumes", "/cores", "/var", "/etc", "/tmp",
        "/private/var", "/private/etc", "/private/tmp", "/usr/local",
    ]

    /// Strips the data volume prefix so both spellings of a path compare equal.
    static func normalize(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        if p == dataVolumePrefix { return "/" }
        if p.hasPrefix(dataVolumePrefix + "/") { p.removeFirst(dataVolumePrefix.count) }
        return p
    }

    /// Returns why `path` can't be removed, or nil if it's fine.
    static func refusal(for path: String, scanRoot: String, home: String = NSHomeDirectory()) -> String? {
        let p = normalize(path)
        let h = normalize(home)
        if p == normalize(scanRoot) {
            return "This is the folder being scanned."
        }
        if protectedPaths.contains(p) {
            return "This is a system folder that macOS needs."
        }
        if p == h {
            return "This is your home folder."
        }
        if h.hasPrefix(p + "/") {
            return "Your home folder is inside this folder."
        }
        if p.hasPrefix("/System/") {
            return "This is part of macOS."
        }
        return nil
    }
}
