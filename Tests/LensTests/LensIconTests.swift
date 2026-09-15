import Foundation
import ImageIO
import Testing

@Test func appIconCoversMacSizesAndRetinaScales() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent("Sources/Lens/Resources/Assets.xcassets/AppIcon.appiconset")
    let data = try Data(contentsOf: directory.appendingPathComponent("Contents.json"))
    let catalog = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(catalog["images"] as? [[String: String]])
    #expect(entries.count == 10)
    var variants = Set<String>()
    for entry in entries {
        let size = try #require(entry["size"])
        let scale = try #require(entry["scale"])
        let points = try #require(Int(size.components(separatedBy: "x")[0]))
        let multiplier = try #require(Int(scale.replacingOccurrences(of: "x", with: "")))
        let filename = try #require(entry["filename"])
        #expect(entry["idiom"] == "mac")
        #expect(size == "\(points)x\(points)")
        #expect([16, 32, 128, 256, 512].contains(points))
        #expect([1, 2].contains(multiplier))
        #expect(variants.insert("\(size)@\(scale)").inserted)
        let source = try #require(CGImageSourceCreateWithURL(directory.appendingPathComponent(filename) as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == points * multiplier)
        #expect(image.height == points * multiplier)
        #expect([CGImageAlphaInfo.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo))
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)] {
            #expect(pixels[(y * image.width + x) * 4 + 3] == 0)
        }
        #expect(pixels[((image.height / 2) * image.width + image.width / 2) * 4 + 3] > 240)
    }
}
