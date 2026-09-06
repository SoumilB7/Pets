import AppKit
import ApplicationServices

// ENGINE-OWNED. "Screen context": what the user is doing right now.
//   • Always: frontmost app name + bundle id (no permission needed).
//   • With Accessibility permission: focused window title, open document,
//     and the page URL in browsers.
// Sampled once a second by the engine; `Context.current` is the latest reading.
// Changes are logged as [context]. Behaviour rules can read `current.category`.

enum Category: String, CaseIterable {
    case code, terminal, browser, chat, docs, media, social, design, other, unknown
    case away      // lock screen / screensaver: nobody is here
}

struct ScreenContext: Equatable {
    var app = ""            // "Code", "Google Chrome"
    var bundle = ""         // "com.microsoft.VSCode"
    var title = ""          // focused window title
    var document = ""       // file path / URL of the open document, if the app exposes it
    var url = ""            // page URL, browsers only
    var category: Category = .unknown
    var windowCount = 0     // usable ledges the pet can see on this desktop
    var idleSeconds = 0     // since the last key / mouse event (no permission needed)

    var summary: String {
        var parts = ["\(app.isEmpty ? "?" : app) [\(category.rawValue)]\(idleSeconds >= 60 ? " idle \(idleSeconds / 60)m" : "")"]
        if !title.isEmpty { parts.append("“\(title)”") }
        if !url.isEmpty { parts.append(url) } else if !document.isEmpty { parts.append(document) }
        return parts.joined(separator: " · ")
    }
}

enum Context {
    static var current = ScreenContext()
    static var lastLogged = ScreenContext()
    static var lastLogTime = Date.distantPast

    // MARK: permission

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that sends the user to System Settings → Privacy → Accessibility.
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: sampling

    /// Refresh `current`. Returns true if something meaningful changed.
    @discardableResult
    static func refresh(windowCount: Int) -> Bool {
        var c = ScreenContext()
        c.windowCount = windowCount
        c.idleSeconds = Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!))
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { return false }   // our own window: keep last reading
        c.app = front.localizedName ?? "?"
        c.bundle = front.bundleIdentifier ?? ""
        if c.bundle == "com.apple.loginwindow" || c.bundle == "com.apple.ScreenSaver.Engine" {
            c.app = "Lock screen"
            c.category = .away
            let changed = current.category != .away
            current = c
            if changed { lastLogged = c; lastLogTime = Date(); Log.w("context", c.summary) }
            return changed
        }

        if accessibilityGranted {
            let appEl = AXUIElementCreateApplication(front.processIdentifier)
            if let win = attr(appEl, kAXFocusedWindowAttribute) ?? attr(appEl, kAXMainWindowAttribute) {
                let winEl = win as! AXUIElement
                c.title = (attr(winEl, kAXTitleAttribute) as? String) ?? ""
                if let doc = attr(winEl, kAXDocumentAttribute) as? String { c.document = doc }
                if isBrowser(c.bundle) { c.url = findURL(in: winEl) }
            }
        }
        c.category = classify(bundle: c.bundle, app: c.app, url: c.url, title: c.title)

        let idleFlip = (c.idleSeconds >= 120) != (current.idleSeconds >= 120)   // crossing the 2-minute idle line counts
        let changed = c.app != current.app || c.title != current.title || c.url != current.url || c.category != current.category || idleFlip
        current = c
        if changed, Date().timeIntervalSince(lastLogTime) > 0.9, c != lastLogged {
            lastLogged = c
            lastLogTime = Date()
            Log.w("context", c.summary)
        }
        return changed
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Depth/size-limited search for a web area's URL or an address bar value.
    private static func findURL(in root: AXUIElement) -> String {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var seen = 0
        while !queue.isEmpty, seen < 400 {
            let (el, depth) = queue.removeFirst()
            seen += 1
            let role = (attr(el, kAXRoleAttribute) as? String) ?? ""
            if role == "AXWebArea", let u = attr(el, "AXURL") {
                if let url = u as? URL { return url.absoluteString }
                if let s = u as? String { return s }
            }
            if role == kAXTextFieldRole as String, let v = attr(el, kAXValueAttribute) as? String,
               v.hasPrefix("http://") || v.hasPrefix("https://") { return v }
            if depth < 7, let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for k in kids.prefix(40) { queue.append((k, depth + 1)) }
            }
        }
        return ""
    }

    // MARK: classification

    static func isBrowser(_ b: String) -> Bool {
        ["com.google.Chrome", "com.brave.Browser", "com.apple.Safari", "org.mozilla.firefox",
         "company.thebrowser.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"].contains { b.hasPrefix($0) }
    }

    static func classify(bundle b: String, app: String, url: String, title: String) -> Category {
        let host = URL(string: url)?.host?.lowercased() ?? ""
        if !host.isEmpty {
            if ["youtube.", "netflix.", "twitch.", "primevideo.", "hulu.", "spotify."].contains(where: host.contains) { return .media }
            if ["twitter.", "x.com", "reddit.", "instagram.", "facebook.", "tiktok.", "threads."].contains(where: host.contains) { return .social }
            if ["github.", "gitlab.", "stackoverflow.", "localhost", "127.0.0.1"].contains(where: host.contains) { return .code }
            if ["docs.google.", "notion.", "confluence.", "figma."].contains(where: host.contains) { return host.contains("figma") ? .design : .docs }
            if ["slack.", "discord.", "web.whatsapp.", "teams.", "mail.google.", "outlook."].contains(where: host.contains) { return .chat }
            return .browser
        }
        if isBrowser(b) { return .browser }
        let table: [(String, Category)] = [
            ("com.microsoft.VSCode", .code), ("com.apple.dt.Xcode", .code), ("com.jetbrains", .code), ("com.todesktop", .code),
            ("dev.zed", .code), ("com.sublimetext", .code), ("com.github.atom", .code), ("com.apple.Terminal", .terminal),
            ("com.googlecode.iterm2", .terminal), ("dev.warp", .terminal), ("com.mitchellh.ghostty", .terminal),
            ("net.kovidgoyal.kitty", .terminal), ("com.tinyspeck.slackmacgap", .chat), ("com.apple.MobileSMS", .chat),
            ("com.hnc.Discord", .chat), ("us.zoom.xos", .chat), ("com.microsoft.teams", .chat), ("com.apple.mail", .chat),
            ("net.whatsapp", .chat), ("ru.keepcoder.Telegram", .chat), ("com.apple.Notes", .docs), ("notion.id", .docs),
            ("md.obsidian", .docs), ("com.apple.iWork", .docs), ("com.microsoft.Word", .docs), ("com.microsoft.Excel", .docs),
            ("com.apple.Preview", .docs), ("com.spotify.client", .media), ("com.apple.Music", .media), ("com.apple.TV", .media),
            ("com.apple.QuickTimePlayerX", .media), ("com.figma", .design), ("com.bohemiancoding.sketch", .design),
            ("com.adobe", .design), ("com.anthropic.claudefordesktop", .chat),
        ]
        for (prefix, cat) in table where b.hasPrefix(prefix) { return cat }
        return b.isEmpty ? .unknown : .other
    }
}
