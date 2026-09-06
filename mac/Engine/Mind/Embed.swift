import Foundation
import NaturalLanguage

// ENGINE-OWNED · Text → vector.
// Default is Apple's on-device sentence embedding (English, 512-d, no network).
// If that model isn't available, a hashing bag-of-words embedder keeps the
// pipeline alive (worse quality, same shape). Both produce unit vectors so
// cosine similarity is a plain dot product.

protocol Embedder: AnyObject {
    var name: String { get }
    var dim: Int { get }
    func embed(_ text: String) -> [Float]?
}

enum Embed {
    static func normalize(_ v: [Float]) -> [Float] {
        let n = sqrt(v.reduce(0) { $0 + $1 * $1 })
        return n > 0 ? v.map { $0 / n } : v
    }
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }
    /// Keep the first `words` words; embedding models have short input windows.
    static func clip(_ text: String, words: Int) -> String {
        let parts = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return parts.prefix(words).joined(separator: " ")
    }
    /// Choose the best embedder available on this Mac.
    /// Best: centered contextual (BERT-style) + static sentence + character/word hashing,
    /// blended 0.3 / 0.3 / 0.4 — measured to separate "coding", "chat" and "invoice" notes.
    static func makeDefault() -> Embedder {
        let stat = LocalEmbedder()
        let lex = HashEmbedder()
        let ctx = ContextualEmbedder()
        if ctx.available && stat.available {
            return BlendEmbedder(parts: [(ctx, 0.3), (stat, 0.3), (lex, 0.4)])
        }
        if stat.available {
            Log.w("warn", "contextual embedding assets unavailable; using sentence + lexical only")
            return BlendEmbedder(parts: [(stat, 0.5), (lex, 0.5)])
        }
        Log.w("warn", "Apple embedding models unavailable; falling back to hashing embedder")
        return lex
    }
}

final class LocalEmbedder: Embedder {
    let name = "apple-sentence-en"
    private let model: NLEmbedding?
    var dim: Int { model?.dimension ?? 512 }
    var available: Bool { model != nil }

    init() { model = NLEmbedding.sentenceEmbedding(for: .english) }

    func embed(_ text: String) -> [Float]? {
        guard let m = model else { return nil }
        let t = Embed.clip(text, words: 350)
        guard !t.isEmpty, let v = m.vector(for: t) else { return nil }
        return Embed.normalize(v.map { Float($0) })
    }
}

/// Apple's contextual (transformer) embedding, mean-pooled over tokens and CENTERED:
/// raw vectors all point roughly the same way, so we subtract the mean of a fixed set
/// of everyday sentences before normalising. That restores real discrimination.
final class ContextualEmbedder: Embedder {
    let name = "apple-contextual-en-centered"
    private let model: NLContextualEmbedding?
    private var mean: [Float] = []
    var dim: Int { model?.dimension ?? 512 }
    var available: Bool { model != nil && !mean.isEmpty }
    private static let anchors = [
        "the weather is nice today", "open the file and save it", "send a message to a friend", "read the news article", "write code in the editor",
        "listen to music on the speaker", "buy groceries at the store", "the meeting starts at noon", "fix the bug in the function", "watch a video online",
        "settings and preferences", "search the internet for answers", "reply to the email", "plan the trip next week", "design the new logo",
        "the cat sat on the mat", "install the software update", "chat with the team", "take notes during class", "pay the invoice by friday",
        "a browser tab with documentation", "the terminal shows an error", "photos from the holiday", "a spreadsheet with numbers", "call mom tonight",
        "finish the report", "play a game", "learn a new language", "the database stores vectors", "book a table for dinner",
    ]
    init() {
        guard let m = NLContextualEmbedding(language: .english), m.hasAvailableAssets, (try? m.load()) != nil else {
            model = nil
            NLContextualEmbedding(language: .english)?.requestAssets { r, _ in Log.w("embed", "contextual assets request: \(r.rawValue) (restart to use them)") }
            return
        }
        model = m
        var acc = [Float](repeating: 0, count: m.dimension)
        var n = 0
        for a in ContextualEmbedder.anchors { if let v = rawVector(a) { for i in 0..<acc.count { acc[i] += v[i] }; n += 1 } }
        mean = n > 0 ? acc.map { $0 / Float(n) } : []
    }
    private func rawVector(_ text: String) -> [Float]? {
        guard let m = model, let r = try? m.embeddingResult(for: text, language: .english) else { return nil }
        var sum = [Float](repeating: 0, count: m.dimension); var n = 0
        r.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { v, _ in for i in 0..<v.count { sum[i] += Float(v[i]) }; n += 1; return true }
        return n > 0 ? sum.map { $0 / Float(n) } : nil
    }
    func embed(_ text: String) -> [Float]? {
        let t = Embed.clip(text, words: 200)
        guard !t.isEmpty, let v = rawVector(t) else { return nil }
        return Embed.normalize(zip(v, mean).map { $0 - $1 })
    }
}

/// Weighted concatenation of several unit vectors: cosine == Σ weight·cosine_part.
final class BlendEmbedder: Embedder {
    let parts: [(Embedder, Float)]        // (embedder, blend weight); weights should sum to 1
    var name: String { "blend(" + parts.map { "\($0.0.name):\($0.1)" }.joined(separator: "+") + ")" }
    var dim: Int { parts.reduce(0) { $0 + $1.0.dim } }
    init(parts: [(Embedder, Float)]) { self.parts = parts }
    func embed(_ text: String) -> [Float]? {
        var out: [Float] = []
        var any = false
        for (e, w) in parts {
            if let v = e.embed(text) { out += v.map { $0 * sqrt(w) }; any = true }
            else { out += [Float](repeating: 0, count: e.dim) }
        }
        return any ? out : nil
    }
}

/// Concatenation of a semantic vector and a lexical (hashed keyword) vector, each
/// scaled so cosine == 0.64·semantic + 0.36·lexical. Sentence models alone rank
/// "invoice email" near "database docs" because both are "work"; the lexical half
/// makes shared words count.
final class HybridEmbedder: Embedder {
    let semantic: Embedder
    let lexical: Embedder
    let wSem: Float = 0.8, wLex: Float = 0.6   // squares sum to 1
    var name: String { "hybrid(\(semantic.name)+\(lexical.name))" }
    var dim: Int { semantic.dim + lexical.dim }
    init(semantic: Embedder, lexical: Embedder) { self.semantic = semantic; self.lexical = lexical }
    func embed(_ text: String) -> [Float]? {
        guard let s = semantic.embed(text) else { return nil }
        let l = lexical.embed(text) ?? [Float](repeating: 0, count: lexical.dim)
        return s.map { $0 * wSem } + l.map { $0 * wLex }
    }
}

/// Deterministic bag-of-words hashing, 512-d. No model, no download.
final class HashEmbedder: Embedder {
    let name = "hash-bow-512"
    let dim = 512
    func embed(_ text: String) -> [Float]? {
        var v = [Float](repeating: 0, count: dim)
        let stop: Set<String> = ["the", "a", "an", "and", "or", "of", "to", "in", "for", "on", "with", "com", "www", "http", "https", "re", "is", "it", "at", "by"]
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 && !stop.contains($0) }
        guard !words.isEmpty else { return nil }
        func add(_ t: String, _ weight: Float) {
            var h: UInt64 = 1469598103934665603
            for b in t.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
            v[Int(h % UInt64(dim))] += ((h >> 60) & 1 == 0 ? 1 : -1) * weight
        }
        for w in words {
            add(w, 1.0)
            let cs = Array("_" + w + "_")
            if cs.count >= 3 { for i in 0...(cs.count - 3) { add(String(cs[i..<i + 3]), 0.4) } }   // character trigrams
        }
        return Embed.normalize(v)
    }
}
