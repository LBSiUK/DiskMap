import Foundation

/// Saves and loads scan results in a compact binary format, one file per scanned folder.
struct ScanCache {
    static let formatVersion: UInt32 = 1
    private static let magic: UInt32 = 0x444D_4150  // "DMAP"

    let directory: URL

    static var standard: ScanCache {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ScanCache(directory: base.appendingPathComponent("Disk Map/Scans", isDirectory: true))
    }

    func fileURL(for rootPath: String) -> URL {
        let safe = rootPath.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent(safe.isEmpty ? "_" : safe).appendingPathExtension("scan")
    }

    func save(_ result: ScanResult) throws {
        guard let rootPath = result.root.rootPath else { return }
        var w = Writer()
        w.u32(Self.magic)
        w.u32(Self.formatVersion)
        w.f64(result.date.timeIntervalSince1970)
        w.u32(UInt32(result.unreadableCount))
        w.string(rootPath)
        w.node(result.root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try w.data.write(to: fileURL(for: rootPath), options: .atomic)
    }

    /// Returns nil when there's no cache, it's damaged, or it was written by another format version.
    func load(rootPath: String) -> ScanResult? {
        guard let data = try? Data(contentsOf: fileURL(for: rootPath)) else { return nil }
        var r = Reader(data: data)
        guard r.u32() == Self.magic, r.u32() == Self.formatVersion,
              let time = r.f64(), let unreadable = r.u32(), let path = r.string(),
              path == rootPath, let root = r.node(), r.atEnd
        else { return nil }
        root.rootPath = path
        return ScanResult(root: root, unreadableCount: Int(unreadable), date: Date(timeIntervalSince1970: time))
    }

    // MARK: - Encoding

    private struct Writer {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func i64(_ v: Int64) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        mutating func f64(_ v: Double) { withUnsafeBytes(of: v.bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        mutating func string(_ s: String) {
            let bytes = Array(s.utf8)
            u32(UInt32(bytes.count))
            data.append(contentsOf: bytes)
        }
        // Children are written depth first; an explicit stack keeps deep trees off the call stack.
        mutating func node(_ root: FileNode) {
            var stack = [root]
            while let n = stack.popLast() {
                u8(n.kind.rawValue)
                i64(n.size)
                u32(UInt32(n.fileCount))
                string(n.name)
                u32(UInt32(n.children.count))
                stack.append(contentsOf: n.children.reversed())
            }
        }
    }

    private struct Reader {
        let data: Data
        var offset = 0
        init(data: Data) { self.data = data }

        var atEnd: Bool { offset == data.count }

        mutating func bytes(_ n: Int) -> Data? {
            guard n >= 0, offset + n <= data.count else { return nil }
            defer { offset += n }
            return data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + n)
        }
        mutating func u8() -> UInt8? { bytes(1)?.first }
        mutating func u32() -> UInt32? { bytes(4).map { UInt32(littleEndian: $0.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) } }
        mutating func i64() -> Int64? { bytes(8).map { Int64(littleEndian: $0.withUnsafeBytes { $0.loadUnaligned(as: Int64.self) }) } }
        mutating func f64() -> Double? { bytes(8).map { Double(bitPattern: UInt64(littleEndian: $0.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) })) } }
        mutating func string() -> String? {
            guard let n = u32(), let b = bytes(Int(n)) else { return nil }
            return String(decoding: b, as: UTF8.self)
        }

        private struct Header { let kind: FileNode.Kind; let size: Int64; let count: Int; let name: String; let childCount: Int }

        private mutating func header() -> Header? {
            guard let k = u8(), let kind = FileNode.Kind(rawValue: k), let size = i64(),
                  let count = u32(), let name = string(), let children = u32() else { return nil }
            return Header(kind: kind, size: size, count: Int(count), name: name, childCount: Int(children))
        }

        /// Rebuilds the tree bottom-up: a node is created once all its children have been read.
        mutating func node() -> FileNode? {
            var pending: [(header: Header, children: [FileNode])] = []
            guard let first = header() else { return nil }
            pending.append((first, []))
            while true {
                guard let top = pending.last else { return nil }
                if top.children.count < top.header.childCount {
                    guard let h = header() else { return nil }
                    pending.append((h, []))
                    continue
                }
                pending.removeLast()
                let h = top.header
                let built = FileNode(name: h.name, kind: h.kind, size: h.size, fileCount: h.count, children: top.children)
                if pending.isEmpty { return built }
                pending[pending.count - 1].children.append(built)
            }
        }
    }
}
