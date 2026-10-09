import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCoding {
    /// Encodes a PNG. `scale` sets the DPI metadata (72 × scale) so Retina captures open at their point size.
    public static func pngData(from image: CGImage, scale: CGFloat = 1) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * max(scale, 1)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// Loads an image scaled so its longest edge is at most `maxPixelSize`. Never upscales.
    public static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A downscaled PNG for sending to agents.
    public static func downscaledPNG(at url: URL, maxPixelSize: Int) -> Data? {
        guard let image = thumbnail(at: url, maxPixelSize: maxPixelSize) else { return nil }
        return pngData(from: image)
    }
}
