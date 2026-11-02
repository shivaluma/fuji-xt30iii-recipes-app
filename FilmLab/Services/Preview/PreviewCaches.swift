import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Small, deterministic LRU cache (value semantics → easy to test; owned by an actor).
struct LRUCache<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []
    let capacity: Int

    init(capacity: Int) { self.capacity = max(1, capacity) }

    var count: Int { storage.count }
    var keys: [Key] { order }

    mutating func value(for key: Key) -> Value? {
        guard let v = storage[key] else { return nil }
        touch(key)
        return v
    }

    mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        while order.count > capacity {
            storage.removeValue(forKey: order.removeFirst())
        }
    }

    mutating func removeAll(where predicate: (Key) -> Bool) {
        for k in order where predicate(k) { storage.removeValue(forKey: k) }
        order.removeAll(where: predicate)
    }

    mutating func removeAll() { storage.removeAll(); order.removeAll() }

    private mutating func touch(_ key: Key) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }
}

/// On-disk JPEG cache for rendered previews (Caches directory → the OS may purge it).
struct DiskPreviewCache: Sendable {
    let directory: URL
    var byteLimit: Int = 200 * 1024 * 1024

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for key: RenderCacheKey) -> URL {
        directory.appendingPathComponent(key.description).appendingPathExtension("jpg")
    }

    func read(_ key: RenderCacheKey) -> CGImage? {
        let u = url(for: key)
        guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    func write(_ image: CGImage, for key: RenderCacheKey) {
        let u = url(for: key)
        guard let dest = CGImageDestinationCreateWithURL(u as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        prune()
    }

    /// Removes every cached file derived from a source (e.g. when the asset is deleted).
    func invalidate(sourceFingerprint: String) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(sourceFingerprint + "_") {
            try? FileManager.default.removeItem(at: f)
        }
    }

    func removeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func prune() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > byteLimit else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries where total > byteLimit {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}

/// Luminance + RGB histogram computed from the actual rendered (displayed) pixels.
struct Histogram: Sendable, Equatable {
    static let bins = 64
    var red: [Float]
    var green: [Float]
    var blue: [Float]
    var luma: [Float]
    /// Fraction of pixels at the extremes (clipping indicators).
    var clippedShadows: Float
    var clippedHighlights: Float

    /// Samples the image at ≤256 px on the long edge in sRGB.
    static func compute(from image: CGImage) -> Histogram? {
        let longEdge = max(image.width, image.height)
        let scale = min(1, 256 / Double(max(longEdge, 1)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var r = [Float](repeating: 0, count: bins), g = r, b = r, l = r
        var low: Float = 0, high: Float = 0
        let n = w * h
        for i in 0..<n {
            let R = Int(px[i * 4]), G = Int(px[i * 4 + 1]), B = Int(px[i * 4 + 2])
            let Y = (2126 * R + 7152 * G + 722 * B) / 10000
            r[R * bins / 256] += 1; g[G * bins / 256] += 1; b[B * bins / 256] += 1; l[Y * bins / 256] += 1
            if Y <= 2 { low += 1 }
            if R >= 254 || G >= 254 || B >= 254 { high += 1 }
        }
        let peak = max(r.max() ?? 1, g.max() ?? 1, b.max() ?? 1, l.max() ?? 1, 1)
        func norm(_ a: [Float]) -> [Float] { a.map { $0 / peak } }
        return Histogram(red: norm(r), green: norm(g), blue: norm(b), luma: norm(l),
                         clippedShadows: low / Float(n), clippedHighlights: high / Float(n))
    }
}
