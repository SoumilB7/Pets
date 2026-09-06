import AppKit
import ApplicationServices
import CryptoKit

// ENGINE-OWNED · A window becomes text.
// Uses what Context already reads (app, title, url, document, category) and adds a
// capped text sample from the window's accessibility tree. Needs Accessibility
// permission for titles and text; without it a snapshot is app name + category.

struct Snapshot: Codable {
    var nodeId: String            // deterministic UUID from bundle|title|url|document
    var windowId: Int
    var pid: Int32
    var app: String
    var bundle: String
    var title: String
    var url: String
    var document: String
    var category: String
    var desktop: UInt64
    var text: String              // sampled text ("" when excluded / unavailable)
    var hash: String              // sha256 of embedText
    var time: Date

    /// What gets embedded. Starts with what the app IS (so "Code" means programming even
    /// when no window title is available), then the title / url, then sampled text.
    var embedText: String {
        var head = app
        let what = AppKnowledge.describe(bundle: bundle, app: app, category: category)
        if !what.isEmpty { head += " — " + what }
        if !title.isEmpty { head += " · " + title }
        if !url.isEmpty { head += " · " + url } else if !document.isEmpty { head += " · " + document }
        return text.isEmpty ? head : head + "\n" + text
    }
}

/// What common apps are for, in plain words. Feeds the embedding so app nodes carry
/// meaning even before Accessibility gives us titles. Add freely.
enum AppKnowledge {
    static let byBundle: [String: String] = [
        "com.microsoft.VSCode": "Visual Studio Code, code editor for programming and coding, writing software, source code files, developer",
        "com.apple.dt.Xcode": "Xcode, code editor for programming and coding Swift apps, developer",
        "com.todesktop": "Cursor, AI code editor for programming and coding, developer",
        "dev.zed": "Zed, code editor for programming and coding, developer",
        "com.apple.Terminal": "terminal, command line shell, running commands, scripts, developer tools, coding",
        "com.googlecode.iterm2": "terminal, command line shell, running commands, scripts, developer tools, coding",
        "dev.warp": "terminal, command line shell, running commands, developer tools, coding",
        "com.mitchellh.ghostty": "terminal, command line shell, running commands, developer tools, coding",
        "com.brave.Browser": "web browser, browsing websites, research, reading articles, searching the internet, documentation",
        "com.google.Chrome": "web browser, browsing websites, research, reading articles, searching the internet, documentation",
        "com.apple.Safari": "web browser, browsing websites, research, reading articles, searching the internet",
        "org.mozilla.firefox": "web browser, browsing websites, research, reading articles, searching the internet",
        "company.thebrowser.Browser": "Arc web browser, browsing websites, research, reading articles",
        "net.whatsapp.WhatsApp": "WhatsApp, chat messages, messaging friends and groups, replying to people, polls",
        "com.tinyspeck.slackmacgap": "Slack, team chat messages, work conversations, replying to colleagues",
        "com.hnc.Discord": "Discord, chat messages, communities, voice",
        "com.apple.MobileSMS": "Messages, texting, chat, replying to people",
        "com.apple.mail": "email, inbox, replying to mail, correspondence",
        "com.apple.Notes": "notes, writing, personal notes and lists",
        "notion.id": "Notion, notes, documents, planning, writing, wiki",
        "md.obsidian": "Obsidian, notes, writing, knowledge base",
        "com.apple.finder": "Finder, files and folders, organising documents",
        "com.spotify.client": "Spotify, music, listening, playlists",
        "com.apple.Music": "music, listening, playlists",
        "com.figma": "Figma, design, UI mockups, prototypes",
        "us.zoom.xos": "Zoom, video call, meeting",
        "com.anthropic.claudefordesktop": "Claude, AI assistant chat, asking questions, writing and coding help",
        "com.apple.systempreferences": "System Settings, macOS preferences, permissions, configuration",
    ]
    static func describe(bundle: String, app: String, category: String) -> String {
        if let s = byBundle.first(where: { bundle.hasPrefix($0.key) })?.value { return s }
        if app.lowercased().contains("whatsapp") { return byBundle["net.whatsapp.WhatsApp"]! }
        switch category {
        case "code": return "code editor, programming and coding, developer"
        case "terminal": return "terminal, command line, developer tools"
        case "browser": return "web browser, browsing, research, reading"
        case "chat": return "chat, messaging, replying to people"
        case "docs": return "documents, writing, notes"
        case "media": return "media, music, video, entertainment"
        case "social": return "social media, feeds"
        case "design": return "design tool, mockups"
        default: return ""
        }
    }
}

enum Capture {
    static let maxChars = 2000, maxNodes = 300, maxMs = 150.0
    static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXLink", "AXCell", "AXMenuItem"]

    // MARK: ids & hashes

    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Deterministic UUID string for a window identity (Actian ids must be ints or UUIDs).
    static func nodeId(bundle: String, title: String, url: String, document: String) -> String {
        let d = SHA256.hash(data: Data("\(bundle)|\(title)|\(url)|\(document)".utf8))
        var b = [UInt8](d.prefix(16))
        b[6] = (b[6] & 0x0f) | 0x40; b[8] = (b[8] & 0x3f) | 0x80     // version 4 / variant bits
        let hex = b.map { String(format: "%02x", $0) }.joined()
        let i = hex.startIndex
        return "\(hex[i..<hex.index(i, offsetBy: 8)])-\(hex[hex.index(i, offsetBy: 8)..<hex.index(i, offsetBy: 12)])-\(hex[hex.index(i, offsetBy: 12)..<hex.index(i, offsetBy: 16)])-\(hex[hex.index(i, offsetBy: 16)..<hex.index(i, offsetBy: 20)])-\(hex[hex.index(i, offsetBy: 20)...])"
    }

    // MARK: building snapshots

    /// The focused window, from the current context reading.
    static func focused(_ c: ScreenContext, pid: Int32, windowId: Int, desktop: UInt64, withText: Bool) -> Snapshot {
        let text = withText && pid > 0 ? textSample(pid: pid) : ""
        var s = Snapshot(nodeId: "", windowId: windowId, pid: pid, app: c.app, bundle: c.bundle, title: c.title, url: c.url,
                         document: c.document, category: c.category.rawValue, desktop: desktop, text: text, hash: "", time: Date())
        s.nodeId = nodeId(bundle: s.bundle, title: s.title, url: s.url, document: s.document)
        s.hash = sha(s.embedText)
        return s
    }

    /// Chromium apps (Chrome, Brave, Edge, Arc, Electron) keep their accessibility tree off
    /// until a client asks. This flag switches it on; without it they report no windows.
    private static var wokenPids = Set<Int32>()
    static func wake(_ appEl: AXUIElement, pid: Int32) {
        guard !wokenPids.contains(pid) else { return }
        wokenPids.insert(pid)
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// Title-only snapshots for every window of an app (used by the 5-minute sweep).
    static func windows(ofPid pid: Int32, app: String, bundle: String, category: String, desktop: UInt64) -> [Snapshot] {
        guard AXIsProcessTrusted() else { return [] }
        let appEl = AXUIElementCreateApplication(pid)
        var wins = attr(appEl, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if wins.isEmpty {
            wake(appEl, pid: pid)      // Chromium apps answer on the next sweep once their tree is on
            wins = attr(appEl, kAXWindowsAttribute) as? [AXUIElement] ?? []
        }
        guard !wins.isEmpty else { return [] }
        var out: [Snapshot] = []
        for (i, w) in wins.prefix(12).enumerated() {
            let title = (attr(w, kAXTitleAttribute) as? String) ?? ""
            if title.isEmpty { continue }
            let doc = (attr(w, kAXDocumentAttribute) as? String) ?? ""
            var s = Snapshot(nodeId: "", windowId: -1000 - i, pid: pid, app: app, bundle: bundle, title: title, url: "", document: doc,
                             category: category, desktop: desktop, text: "", hash: "", time: Date())
            s.nodeId = nodeId(bundle: bundle, title: title, url: "", document: doc)
            s.hash = sha(s.embedText)
            out.append(s)
        }
        return out
    }

    // MARK: accessibility text sampling

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Breadth-first walk of the focused window, collecting visible text. Hard caps keep it cheap.
    static func textSample(pid: Int32) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let appEl = AXUIElementCreateApplication(pid)
        wake(appEl, pid: pid)
        guard let win = (attr(appEl, kAXFocusedWindowAttribute) ?? attr(appEl, kAXMainWindowAttribute)) else { return "" }
        let start = Date()
        var queue: [AXUIElement] = [win as! AXUIElement]
        var seen = 0
        var pieces: [String] = []
        var chars = 0
        while !queue.isEmpty, seen < maxNodes, chars < maxChars, Date().timeIntervalSince(start) * 1000 < maxMs {
            let el = queue.removeFirst()
            seen += 1
            let role = (attr(el, kAXRoleAttribute) as? String) ?? ""
            if textRoles.contains(role) {
                var s = (attr(el, kAXValueAttribute) as? String) ?? ""
                if s.isEmpty { s = (attr(el, kAXTitleAttribute) as? String) ?? "" }
                if s.isEmpty { s = (attr(el, kAXDescriptionAttribute) as? String) ?? "" }
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count > 1 {
                    let clipped = String(t.prefix(maxChars - chars))
                    pieces.append(clipped)
                    chars += clipped.count + 1
                }
            }
            if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] { queue.append(contentsOf: kids.prefix(60)) }
        }
        return pieces.joined(separator: " ").replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
