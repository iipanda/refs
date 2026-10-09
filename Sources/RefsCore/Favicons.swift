import CoreGraphics
import Foundation
import ImageIO

/// Finds, downloads and caches website icons.
///
/// Icons are fetched from the site itself (never a third-party favicon service), normalised to a
/// 64 px PNG and stored in `<library>/icons/<host>.png`. A failed lookup leaves a `<host>.none`
/// marker so the site isn't asked again for a week.
public final class FaviconCache: @unchecked Sendable {
    public static let pixelSize = 64
    static let retryInterval: TimeInterval = 7 * 24 * 3600

    public let folder: URL
    private let session: URLSession

    public init(libraryRoot: URL, session: URLSession = FaviconCache.makeSession()) {
        folder = libraryRoot.appendingPathComponent("icons", isDirectory: true)
        self.session = session
    }

    public func iconURL(host: String) -> URL {
        folder.appendingPathComponent("\(Self.safeName(host)).png")
    }

    public func cachedIcon(host: String) -> URL? {
        let url = iconURL(host: host)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether a lookup should be attempted: no icon yet, and no recent failure.
    public func needsFetch(host: String) -> Bool {
        guard cachedIcon(host: host) == nil else { return false }
        let marker = markerURL(host: host)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path),
              let date = attrs[.modificationDate] as? Date
        else { return true }
        return Date().timeIntervalSince(date) > Self.retryInterval
    }

    /// Looks up the icon for the site `pageURL` belongs to and caches it under `host`.
    /// Returns the cached file, or nil if the site has no usable icon.
    @discardableResult
    public func fetch(host: String, pageURL: String) async -> URL? {
        guard let origin = Self.origin(of: pageURL) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var candidates: [URL] = []
        if let (html, finalURL) = await fetchHTML(origin) {
            candidates = FaviconParser.candidates(inHTML: html, baseURL: finalURL)
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: origin)?.absoluteURL, !candidates.contains(fallback) {
            candidates.append(fallback)
        }

        for candidate in candidates.prefix(6) {
            guard let data = await fetchData(candidate),
                  let png = Self.normalizedPNG(from: data)
            else { continue }
            let destination = iconURL(host: host)
            do {
                try png.write(to: destination, options: .atomic)
                try? FileManager.default.removeItem(at: markerURL(host: host))
                return destination
            } catch {
                return nil
            }
        }
        FileManager.default.createFile(atPath: markerURL(host: host).path, contents: Data())
        return nil
    }

    // MARK: - Networking

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        ]
        return URLSession(configuration: configuration)
    }

    private func fetchHTML(_ url: URL) async -> (String, URL)? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        // The <head> is all that matters; don't decode megabytes of body.
        let head = data.prefix(512 * 1024)
        let html = String(decoding: head, as: UTF8.self)
        return (html, http.url ?? url)
    }

    private func fetchData(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 2 * 1024 * 1024
        else { return nil }
        return data
    }

    // MARK: - Helpers

    private func markerURL(host: String) -> URL {
        folder.appendingPathComponent("\(Self.safeName(host)).none")
    }

    static func origin(of pageURL: String) -> URL? {
        guard var components = URLComponents(string: pageURL),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    static func safeName(_ host: String) -> String {
        String(host.lowercased().map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    }

    /// Decodes any format ImageIO understands (ICO, PNG, GIF, JPEG, WebP), picks the largest frame,
    /// and re-encodes it as a square PNG. Tiny icons are rejected.
    static func normalizedPNG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var bestIndex = 0
        var bestWidth = 0
        for index in 0..<count {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
            if width > bestWidth { bestWidth = width; bestIndex = index }
        }
        guard bestWidth >= 16, let image = CGImageSourceCreateImageAtIndex(source, bestIndex, nil) else { return nil }

        let size = pixelSize
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        let scale = min(CGFloat(size) / CGFloat(image.width), CGFloat(size) / CGFloat(image.height))
        let width = CGFloat(image.width) * scale
        let height = CGFloat(image.height) * scale
        let rect = CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height)
        context.draw(image, in: rect)

        // Dark glyphs on transparency (GitHub, many SaaS logos) vanish on a dark sidebar,
        // so they get a light rounded tile behind them.
        if needsLightBacking(context) {
            context.clear(CGRect(x: 0, y: 0, width: size, height: size))
            let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                              cornerWidth: CGFloat(size) * 0.22, cornerHeight: CGFloat(size) * 0.22, transform: nil)
            context.addPath(tile)
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fillPath()
            context.draw(image, in: rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.14))
        }
        guard let output = context.makeImage() else { return nil }
        return ImageCoding.pngData(from: output)
    }

    /// True when at least a quarter of the icon is transparent and its visible pixels are mostly dark.
    static func needsLightBacking(_ context: CGContext) -> Bool {
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        var transparent = 0
        var visible = 0
        var luminance = 0.0
        for y in 0..<context.height {
            for x in 0..<context.width {
                let offset = y * context.bytesPerRow + x * 4
                let alpha = Double(pixels[offset + 3]) / 255
                if alpha < 0.1 { transparent += 1; continue }
                // Premultiplied, so divide by alpha to get the real colour.
                let r = Double(pixels[offset]) / 255 / alpha
                let g = Double(pixels[offset + 1]) / 255 / alpha
                let b = Double(pixels[offset + 2]) / 255 / alpha
                luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
                visible += 1
            }
        }
        let total = context.width * context.height
        guard visible > 0, Double(transparent) / Double(total) >= 0.25 else { return false }
        return luminance / Double(visible) < 0.3
    }
}

/// Extracts icon links from a page's HTML, best first.
public enum FaviconParser {
    public static func candidates(inHTML html: String, baseURL: URL) -> [URL] {
        struct Candidate { var url: URL; var score: Int }
        var found: [Candidate] = []

        for tag in linkTags(in: html) {
            let attributes = self.attributes(of: tag)
            guard let rel = attributes["rel"]?.lowercased(), let href = attributes["href"], !href.isEmpty,
                  let url = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines), relativeTo: baseURL)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http"
            else { continue }
            let rels = Set(rel.split(whereSeparator: \.isWhitespace).map(String.init))
            // mask-icon is a monochrome SVG for Safari pinned tabs; SVGs in general aren't decodable here.
            guard rels.contains("icon") || rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed"),
                  !rels.contains("mask-icon"),
                  !url.path.lowercased().hasSuffix(".svg"),
                  attributes["type"]?.lowercased() != "image/svg+xml"
            else { continue }

            let size = largestSize(attributes["sizes"])
            var score: Int
            if rels.contains("apple-touch-icon") || rels.contains("apple-touch-icon-precomposed") {
                score = 1_000 + (size ?? 180)
            } else {
                score = size ?? 32
            }
            // Prefer icons around 64–256 px; very large ones are usually fine, but tiny ones look blurry.
            if let size, size < 32 { score -= 500 }
            found.append(Candidate(url: url, score: score))
        }

        var seen = Set<URL>()
        return found.sorted { $0.score > $1.score }.map(\.url).filter { seen.insert($0).inserted }
    }

    private static func linkTags(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "<link\\b[^>]*>", options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { Range($0.range, in: html).map { String(html[$0]) } }
    }

    private static func attributes(of tag: String) -> [String: String] {
        let pattern = "([a-zA-Z-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        var result: [String: String] = [:]
        for match in regex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let nameRange = Range(match.range(at: 1), in: tag) else { continue }
            let value = (2...4).lazy.compactMap { Range(match.range(at: $0), in: tag) }.first.map { String(tag[$0]) } ?? ""
            result[tag[nameRange].lowercased()] = value
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        return result
    }

    /// `sizes="16x16 32x32"` → 32. `any` and missing values give nil.
    private static func largestSize(_ sizes: String?) -> Int? {
        guard let sizes else { return nil }
        return sizes.lowercased().split(whereSeparator: \.isWhitespace)
            .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
            .max()
    }
}
