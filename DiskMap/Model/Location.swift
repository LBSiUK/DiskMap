import Foundation

/// A place in the sidebar that can be scanned.
struct Location: Identifiable, Hashable, Codable {
    let name: String
    let path: String
    let symbol: String
    let isCustom: Bool

    var id: String { path }

    /// The startup disk. Its files live on the data volume, so that's what gets scanned.
    static var startupDisk: Location {
        let data = "/System/Volumes/Data"
        let path = FileManager.default.fileExists(atPath: data) ? data : "/"
        let name = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? "Macintosh HD"
        return Location(name: name, path: path, symbol: "internaldrive", isCustom: false)
    }

    static var home: Location {
        Location(name: "Home", path: NSHomeDirectory(), symbol: "house", isCustom: false)
    }

    static func custom(_ url: URL) -> Location {
        Location(name: url.lastPathComponent, path: url.path, symbol: "folder", isCustom: true)
    }
}

/// Size and free space for the volume a path lives on.
struct VolumeStats: Equatable {
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }

    init?(path: String) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        self.total = Int64(total)
        self.available = available
    }
}

extension Int64 {
    var bytes: String { self == 0 ? "0 bytes" : formatted(.byteCount(style: .file)) }
}
