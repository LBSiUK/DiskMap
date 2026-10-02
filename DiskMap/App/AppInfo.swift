import AppKit

enum AppInfo {
    static let copyright = "Copyright © 2026 LBSi UK / Leon Brahams"
    static let website = URL(string: "https://github.com/LBSiUK/DiskMap")!

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// The standard About window, with the GitHub link under the copyright.
    static func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: "github.com/LBSiUK/DiskMap",
            attributes: [.link: website, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .init(rawValue: "Copyright"): copyright])
        NSApp.activate()
    }
}
