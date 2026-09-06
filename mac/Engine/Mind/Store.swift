import Foundation

// ENGINE-OWNED · Vector stores.
//   VectorStore  – the protocol the Mind talks to
//   LocalStore   – JSON on disk + brute-force cosine; always present; source of truth
//   ActianStore  – Actian VectorAI DB over its REST API (Qdrant-compatible shapes)
// Vectors are unit-length, so cosine == dot.

struct Point: Codable {
    var id: String                 // UUID string (Actian accepts ints or UUIDs)
    var vector: [Float]
    var payload: [String: String]  // flat string map keeps both stores simple
}

struct Hit {
    let id: String
    let score: Float
    let payload: [String: String]
}

enum StoreError: Error, CustomStringConvertible {
    case http(Int, String), network(String), decode(String)
    var description: String {
        switch self {
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .network(let m): return "network: \(m)"
        case .decode(let m): return "decode: \(m)"
        }
    }
}

protocol VectorStore: AnyObject {
    var label: String { get }
    func ensureCollection(_ name: String, dim: Int) throws
    func upsert(_ collection: String, _ points: [Point]) throws
    func search(_ collection: String, vector: [Float], limit: Int, filter: [String: String]) throws -> [Hit]
    func delete(_ collection: String, ids: [String]) throws
    func count(_ collection: String) throws -> Int
}

// MARK: - Local

final class LocalStore: VectorStore {
    let label = "local"
    private var cols: [String: [String: Point]] = [:]
    private let url: URL
    private var saveWork: DispatchWorkItem?
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([String: [String: Point]].self, from: d) { cols = c }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: w)
    }
    func saveNow() {
        lock.lock(); let snapshot = cols; lock.unlock()
        if let d = try? JSONEncoder().encode(snapshot) { try? d.write(to: url, options: .atomic) }
    }

    func ensureCollection(_ name: String, dim: Int) throws {
        lock.lock(); defer { lock.unlock() }
        if cols[name] == nil { cols[name] = [:] }
    }
    func upsert(_ collection: String, _ points: [Point]) throws {
        lock.lock()
        var c = cols[collection] ?? [:]
        for p in points { c[p.id] = p }
        cols[collection] = c
        lock.unlock()
        scheduleSave()
    }
    func search(_ collection: String, vector: [Float], limit: Int, filter: [String: String]) throws -> [Hit] {
        lock.lock(); let c = cols[collection] ?? [:]; lock.unlock()
        var hits: [Hit] = []
        hits.reserveCapacity(c.count)
        for p in c.values {
            if !filter.isEmpty && filter.contains(where: { p.payload[$0.key] != $0.value }) { continue }
            hits.append(Hit(id: p.id, score: Embed.dot(vector, p.vector), payload: p.payload))
        }
        hits.sort { $0.score > $1.score }
        return Array(hits.prefix(limit))
    }
    func delete(_ collection: String, ids: [String]) throws {
        lock.lock()
        for id in ids { cols[collection]?[id] = nil }
        lock.unlock()
        scheduleSave()
    }
    func count(_ collection: String) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        return cols[collection]?.count ?? 0
    }
    /// Local-only helpers (the remote store never needs these).
    func all(_ collection: String) -> [Point] {
        lock.lock(); defer { lock.unlock() }
        return Array((cols[collection] ?? [:]).values)
    }
    func get(_ collection: String, _ id: String) -> Point? {
        lock.lock(); defer { lock.unlock() }
        return cols[collection]?[id]
    }
}

// MARK: - Actian VectorAI DB

final class ActianStore: VectorStore {
    let label = "actian"
    let endpoint: URL
    let token: String
    private(set) var reachable = false
    private(set) var lastError = ""
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        return URLSession(configuration: c)
    }()

    init(endpoint: URL, token: String) { self.endpoint = endpoint; self.token = token }

    /// GET /collections — used as the health probe.
    @discardableResult
    func health() -> Bool {
        do { _ = try request("GET", "/collections", body: nil as String?); reachable = true; lastError = ""; return true }
        catch { reachable = false; lastError = "\(error)"; return false }
    }

    private func request<B: Encodable>(_ method: String, _ path: String, body: B?) throws -> Data {
        var req = URLRequest(url: endpoint.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let b = body { req.httpBody = try JSONEncoder().encode(b) }
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, URLResponse?, Error?) = (nil, nil, nil)
        session.dataTask(with: req) { d, r, e in out = (d, r, e); sem.signal() }.resume()
        sem.wait()
        if let e = out.2 { reachable = false; lastError = e.localizedDescription; throw StoreError.network(e.localizedDescription) }
        let code = (out.1 as? HTTPURLResponse)?.statusCode ?? 0
        let data = out.0 ?? Data()
        guard (200..<300).contains(code) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            if code == 404 { throw StoreError.http(404, msg) }
            reachable = false; lastError = "HTTP \(code)"
            throw StoreError.http(code, msg)
        }
        reachable = true
        return data
    }

    private struct Empty: Encodable {}

    func ensureCollection(_ name: String, dim: Int) throws {
        do { _ = try request("GET", "/collections/\(name)", body: nil as Empty?); return }
        catch StoreError.http(404, _) { /* create below */ }
        struct Body: Encodable { struct V: Encodable { let size: Int; let distance: String }; let vectors: V }
        _ = try request("PUT", "/collections/\(name)", body: Body(vectors: .init(size: dim, distance: "Cosine")))
        Log.w("store", "actian: created collection \(name) (\(dim)-d, Cosine)")
    }

    func upsert(_ collection: String, _ points: [Point]) throws {
        struct Body: Encodable { let points: [Point] }
        _ = try request("PUT", "/collections/\(collection)/points", body: Body(points: points))
    }

    func search(_ collection: String, vector: [Float], limit: Int, filter: [String: String]) throws -> [Hit] {
        struct Match: Encodable { let value: String }
        struct Cond: Encodable { let key: String; let match: Match }
        struct Filter: Encodable { let must: [Cond] }
        struct Body: Encodable { let vector: [Float]; let limit: Int; let filter: Filter?; let with_payload: Bool }
        let f = filter.isEmpty ? nil : Filter(must: filter.map { Cond(key: $0.key, match: Match(value: $0.value)) })
        let data = try request("POST", "/collections/\(collection)/points/search", body: Body(vector: vector, limit: limit, filter: f, with_payload: true))
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [[String: Any]] else { throw StoreError.decode("search result") }
        return result.compactMap { r in
            guard let score = (r["score"] as? NSNumber)?.floatValue else { return nil }
            let id = (r["id"] as? String) ?? String(describing: r["id"] ?? "")
            let payload = (r["payload"] as? [String: Any])?.mapValues { "\($0)" } ?? [:]
            return Hit(id: id, score: score, payload: payload)
        }
    }

    func delete(_ collection: String, ids: [String]) throws {
        struct Body: Encodable { let points: [String] }
        _ = try request("POST", "/collections/\(collection)/points/delete", body: Body(points: ids))
    }

    func count(_ collection: String) throws -> Int {
        let data = try request("GET", "/collections/\(collection)", body: nil as Empty?)
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let result = obj?["result"] as? [String: Any]
        return (result?["points_count"] as? NSNumber)?.intValue ?? (result?["vectors_count"] as? NSNumber)?.intValue ?? -1
    }
}
