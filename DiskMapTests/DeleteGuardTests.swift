import Testing
@testable import Disk_Map

struct DeleteGuardTests {
    let home = "/Users/sam"
    let root = "/System/Volumes/Data"

    @Test(arguments: ["/", "/System", "/Library", "/Applications", "/Users", "/private", "/usr", "/opt",
                      "/System/Volumes/Data/Applications", "/System/Volumes/Data/Users", "/System/Library/Fonts"])
    func systemFoldersAreRefused(path: String) {
        #expect(DeleteGuard.refusal(for: path, scanRoot: root, home: home) != nil)
    }

    @Test func homeAndScanRootAreRefused() {
        #expect(DeleteGuard.refusal(for: "/Users/sam", scanRoot: root, home: home) != nil)
        #expect(DeleteGuard.refusal(for: "/System/Volumes/Data/Users/sam", scanRoot: root, home: home) != nil)
        #expect(DeleteGuard.refusal(for: "/System/Volumes/Data", scanRoot: root, home: home) != nil)
        #expect(DeleteGuard.refusal(for: "/Users/sam/Movies", scanRoot: "/Users/sam/Movies", home: home) != nil)
    }

    @Test(arguments: ["/Users/sam/Downloads/big.iso", "/Users/sam/Library/Caches",
                      "/System/Volumes/Data/Users/sam/Movies/clip.mov", "/Applications/Some Game.app",
                      "/Library/Developer/CoreSimulator/Caches", "/opt/homebrew/Cellar/old"])
    func ordinaryItemsAreAllowed(path: String) {
        #expect(DeleteGuard.refusal(for: path, scanRoot: root, home: home) == nil)
    }

    @Test func trailingSlashesAndDotsDoNotSlipThrough() {
        #expect(DeleteGuard.refusal(for: "/Applications/", scanRoot: root, home: home) != nil)
        #expect(DeleteGuard.refusal(for: "/Users/sam/Downloads/..", scanRoot: root, home: home) != nil)
    }
}
