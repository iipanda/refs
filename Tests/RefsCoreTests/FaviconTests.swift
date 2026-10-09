import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import RefsCore

@Suite struct FaviconParserTests {
    let base = URL(string: "https://example.com/products/")!

    @Test func ranksAppleTouchIconThenLargestIcon() {
        let html = """
            <html><head>
            <link rel="icon" href="/favicon-16.png" sizes="16x16">
            <link rel="icon" type="image/png" href="/favicon-32.png" sizes="32x32">
            <LINK REL='apple-touch-icon' HREF='/apple.png'>
            <link rel="icon" href="/big.png" sizes="192x192">
            </head></html>
            """
        let urls = FaviconParser.candidates(inHTML: html, baseURL: base).map(\.absoluteString)
        #expect(urls == [
            "https://example.com/apple.png",
            "https://example.com/big.png",
            "https://example.com/favicon-32.png",
            "https://example.com/favicon-16.png",
        ])
    }

    @Test func resolvesRelativeAndProtocolRelativeHrefs() {
        let html = """
            <link rel="shortcut icon" href="img/icon.png">
            <link rel="icon" href="//cdn.example.com/i.png?v=1&amp;x=2" sizes="48x48">
            """
        let urls = FaviconParser.candidates(inHTML: html, baseURL: base).map(\.absoluteString)
        #expect(urls == ["https://cdn.example.com/i.png?v=1&x=2", "https://example.com/products/img/icon.png"])
    }

    @Test func skipsSVGAndMaskIconsAndOtherLinks() {
        let html = """
            <link rel="stylesheet" href="/a.css">
            <link rel="mask-icon" href="/pin.svg" color="#000">
            <link rel="icon" href="/icon.svg" type="image/svg+xml">
            <link rel="icon" href="data:image/png;base64,AAAA">
            <link rel="preload" href="/font.woff2">
            """
        #expect(FaviconParser.candidates(inHTML: html, baseURL: base).isEmpty)
    }
}

@Suite struct FaviconCacheTests {
    @Test func originDropsPathQueryAndCredentials() {
        #expect(FaviconCache.origin(of: "https://user:pw@www.stripe.com/pay?x=1#y")?.absoluteString == "https://www.stripe.com/")
        #expect(FaviconCache.origin(of: "file:///etc/hosts") == nil)
        #expect(FaviconCache.origin(of: "not a url") == nil)
    }

    @Test func safeNameKeepsHostsFilesystemSafe() {
        #expect(FaviconCache.safeName("Example.COM") == "example.com")
        #expect(FaviconCache.safeName("../../x") == ".._.._x")
    }

    @Test func normalizesLargestFrameToSquarePNG() throws {
        // A wide image checks scaling and letterboxing into the square.
        let context = CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        let input = try #require(ImageCoding.pngData(from: context.makeImage()!))

        let output = try #require(FaviconCache.normalizedPNG(from: input))
        let source = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == FaviconCache.pixelSize)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == FaviconCache.pixelSize)

        #expect(FaviconCache.normalizedPNG(from: Data("<html>".utf8)) == nil)
    }

    @Test func darkTransparentIconsGetALightTile() throws {
        func icon(_ gray: CGFloat) -> Data {
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
            return ImageCoding.pngData(from: context.makeImage()!)!
        }
        func cornerAlpha(_ png: Data) throws -> UInt8 {
            let image = try #require(CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            // A pixel just inside the left edge, halfway up: outside the glyph, inside the tile.
            return context.data!.bindMemory(to: UInt8.self, capacity: 64 * 64 * 4)[(32 * 64 + 2) * 4 + 3]
        }
        #expect(try cornerAlpha(#require(FaviconCache.normalizedPNG(from: icon(0.05)))) == 255)
        #expect(try cornerAlpha(#require(FaviconCache.normalizedPNG(from: icon(0.9)))) == 0)
    }

    @Test func failureMarkerSuppressesRetries() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("refs-fav-\(UUID())")
        let cache = FaviconCache(libraryRoot: root)
        #expect(cache.needsFetch(host: "example.com"))
        try FileManager.default.createDirectory(at: cache.folder, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cache.folder.appendingPathComponent("example.com.none").path, contents: Data())
        #expect(!cache.needsFetch(host: "example.com"))
    }
}
