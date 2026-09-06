import AppKit

// ENGINE-OWNED. Read-only access to macOS desktops ("Spaces"), including
// fullscreen apps, which macOS treats as their own desktops.
// Uses two private-but-stable SkyLight calls resolved at runtime (the same ones
// AltTab / Rectangle rely on). If they're missing, `available` is false and the
// pet simply follows you everywhere like before.

enum Spaces {
    struct Info { let id: UInt64; let fullscreen: Bool }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias ActiveFn = @convention(c) (Int32) -> UInt64
    private typealias ListFn = @convention(c) (Int32) -> Unmanaged<CFArray>

    private static let fns: (cid: Int32, active: ActiveFn, list: ListFn)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let c = dlsym(h, "CGSMainConnectionID"),
              let a = dlsym(h, "CGSGetActiveSpace"),
              let l = dlsym(h, "CGSCopyManagedDisplaySpaces") else { return nil }
        let cid = unsafeBitCast(c, to: ConnFn.self)()
        return (cid, unsafeBitCast(a, to: ActiveFn.self), unsafeBitCast(l, to: ListFn.self))
    }()

    static var available: Bool { fns != nil }

    /// The desktop the user is looking at right now.
    static func active() -> UInt64 { fns.map { $0.active($0.cid) } ?? 0 }

    /// All desktops in Mission Control order (left to right), across displays.
    static func list() -> [Info] {
        guard let f = fns, let displays = f.list(f.cid).takeRetainedValue() as? [[String: Any]] else { return [] }
        var out: [Info] = []
        for d in displays {
            for s in d["Spaces"] as? [[String: Any]] ?? [] {
                guard let id = (s["id64"] as? NSNumber)?.uint64Value ?? (s["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
                let type = (s["type"] as? NSNumber)?.intValue ?? 0
                if type == 0 || type == 4 { out.append(Info(id: id, fullscreen: type == 4)) }   // 0 desktop, 4 fullscreen app
            }
        }
        return out
    }

    static func index(of id: UInt64) -> Int? { list().firstIndex { $0.id == id } }
}
