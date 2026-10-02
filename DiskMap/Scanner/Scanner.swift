import Darwin
import Foundation

struct ScanProgress: Sendable, Equatable {
    var folders = 0
    var bytes: Int64 = 0
    var currentPath = ""
}

struct ScanResult: Sendable {
    let root: FileNode
    let unreadableCount: Int
    let date: Date
}

/// Walks a folder tree with `getattrlistbulk`, which returns a whole directory's
/// names, types and sizes per call. Stays on one volume, never follows symbolic
/// links, counts hard-linked files once and records folders it can't open.
final class Scanner: @unchecked Sendable {
    let rootPath: String
    /// Files smaller than this are grouped into one "small files" entry per folder.
    let smallFileThreshold: Int64
    /// Folders this many levels down or less scan their subfolders in parallel.
    let parallelDepth: Int

    private let lock = NSLock()
    private var progress = ScanProgress()
    private var unreadable = 0
    private var seenLinks = Set<FileKey>()
    private var rootDevice: dev_t = 0

    private struct FileKey: Hashable { let device: Int32; let inode: UInt64 }

    init(rootPath: String, smallFileThreshold: Int64 = 1_000_000, parallelDepth: Int = 3) {
        self.rootPath = rootPath
        self.smallFileThreshold = smallFileThreshold
        self.parallelDepth = parallelDepth
    }

    var currentProgress: ScanProgress { lock.withLock { progress } }

    /// Scans the tree. `onProgress` is called about ten times a second while it runs.
    func run(onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async throws -> ScanResult {
        var st = stat()
        guard lstat(rootPath, &st) == 0 else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: rootPath])
        }
        rootDevice = st.st_dev

        let reporter = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                onProgress(currentProgress)
            }
        }
        defer { reporter.cancel() }

        let name = rootPath == "/" ? "/" : (rootPath as NSString).lastPathComponent
        let scanned = await scanFolder(path: rootPath, name: name, depth: 0)
        try Task.checkCancellation()
        guard let root = scanned, root.kind == .folder else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: rootPath])
        }
        root.rootPath = rootPath
        onProgress(currentProgress)
        return ScanResult(root: root, unreadableCount: lock.withLock { unreadable }, date: Date())
    }

    // MARK: - Walking

    private func scanFolder(path: String, name: String, depth: Int) async -> FileNode? {
        if Task.isCancelled { return nil }
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 {
            lock.withLock { unreadable += 1 }
            return FileNode(name: name, kind: .unreadable, size: 0)
        }
        var st = stat()
        if fstat(fd, &st) != 0 || st.st_dev != rootDevice {
            close(fd)
            return nil  // another volume mounted here
        }
        let listing = readEntries(fd: fd)
        close(fd)

        lock.withLock {
            progress.folders += 1
            progress.bytes += listing.fileBytes
            progress.currentPath = path
        }

        let base = path.hasSuffix("/") ? path : path + "/"
        var folders: [FileNode] = []
        if depth < parallelDepth {
            folders = await withTaskGroup(of: FileNode?.self) { group in
                for sub in listing.folders {
                    group.addTask { await self.scanFolder(path: base + sub, name: sub, depth: depth + 1) }
                }
                var out: [FileNode] = []
                for await node in group { if let node { out.append(node) } }
                return out
            }
        } else {
            for sub in listing.folders {
                if let node = await scanFolder(path: base + sub, name: sub, depth: depth + 1) { folders.append(node) }
            }
        }

        var children = folders + listing.bigFiles
        if listing.smallCount > 0 {
            children.append(FileNode(name: "", kind: .smallFiles, size: listing.smallBytes, fileCount: listing.smallCount))
        }
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        return FileNode(name: name, kind: .folder, size: total, children: children)
    }

    private struct Listing {
        var folders: [String] = []
        var bigFiles: [FileNode] = []
        var smallCount = 0
        var smallBytes: Int64 = 0
        var fileBytes: Int64 = 0
    }

    // Attribute bits (sys/attr.h).
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnDevID: UInt32 = 0x0000_0002
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnError: UInt32 = 0x2000_0000
    private static let cmnReturnedAttrs: UInt32 = 0x8000_0000
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let typeRegular: UInt32 = 1
    private static let typeDirectory: UInt32 = 2

    private func readEntries(fd: Int32) -> Listing {
        var list = attrlist()
        list.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        list.commonattr = Self.cmnReturnedAttrs | Self.cmnName | Self.cmnError | Self.cmnDevID | Self.cmnObjType | Self.cmnFileID
        list.fileattr = Self.fileLinkCount | Self.fileAllocSize

        let bufferSize = 128 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { buffer.deallocate() }

        var out = Listing()
        while true {
            let count = getattrlistbulk(fd, &list, buffer, bufferSize, 0)
            if count <= 0 { break }
            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                parse(entry, into: &out)
                entry += length
            }
        }
        return out
    }

    private func parse(_ entry: UnsafeMutableRawPointer, into out: inout Listing) {
        var p = entry + 4
        let returnedCommon = p.loadUnaligned(as: UInt32.self)
        let returnedFile = (p + 12).loadUnaligned(as: UInt32.self)
        p += MemoryLayout<attribute_set_t>.size

        if returnedCommon & Self.cmnError != 0 {
            let error = p.loadUnaligned(as: UInt32.self)
            p += 4
            if error != 0 { return }
        }
        var name = ""
        if returnedCommon & Self.cmnName != 0 {
            let offset = Int(p.loadUnaligned(as: Int32.self))
            name = String(cString: (p + offset).assumingMemoryBound(to: CChar.self))
            p += MemoryLayout<attrreference_t>.size
        }
        var device: Int32 = 0
        if returnedCommon & Self.cmnDevID != 0 {
            device = p.loadUnaligned(as: Int32.self)
            p += 4
        }
        var type: UInt32 = 0
        if returnedCommon & Self.cmnObjType != 0 {
            type = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        var inode: UInt64 = 0
        if returnedCommon & Self.cmnFileID != 0 {
            inode = p.loadUnaligned(as: UInt64.self)
            p += 8
        }

        if type == Self.typeDirectory {
            out.folders.append(name)
            return
        }

        var links: UInt32 = 1
        var size: Int64 = 0
        if returnedFile & Self.fileLinkCount != 0 {
            links = p.loadUnaligned(as: UInt32.self)
            p += 4
        }
        if returnedFile & Self.fileAllocSize != 0 {
            size = p.loadUnaligned(as: Int64.self)
        }
        if type == Self.typeRegular && links > 1 {
            let key = FileKey(device: device, inode: inode)
            let isNew = lock.withLock { seenLinks.insert(key).inserted }
            if !isNew { return }
        }

        out.fileBytes += size
        if size >= smallFileThreshold {
            out.bigFiles.append(FileNode(name: name, kind: .file, size: size))
        } else {
            out.smallCount += 1
            out.smallBytes += size
        }
    }
}
