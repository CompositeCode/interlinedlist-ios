//
//  ImageUploadProcessor.swift
//  InterlinedList
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageUploadProcessor {
    /// Fallback rungs, largest first. The active ladder is derived from the
    /// server's `maxPixels` cap, so anything above it is dropped — the backend
    /// resizes every upload to that cap anyway, and sending more just costs the
    /// user bytes and time.
    static let opaqueDimensionLadder: [CGFloat] = [2048, 1600, 1200, 1000, 800]
    static let opaqueQualityLadder: [CGFloat] = [0.85, 0.7, 0.55, 0.4]
    static let alphaDimensionLadder: [CGFloat] = [1600, 1200, 1000, 800, 600, 400]

    /// The server cap becomes the first rung; the standard rungs below it follow.
    /// Rungs at or above the cap are pointless, so they're dropped.
    static func dimensionLadder(_ base: [CGFloat], maxPixels: CGFloat) -> [CGFloat] {
        [maxPixels] + base.filter { $0 < maxPixels }
    }

    /// `limits` defaults to whatever `GET /api/limits` last reported (the
    /// documented fallback until it answers). It is a parameter so the ladder
    /// logic stays a pure function under test.
    static func process(_ inputData: Data,
                        limits: ImageUploadLimits = ServerLimitsStore.shared.imageLimits) -> (data: Data, mimeType: String)? {
        guard let source = CGImageSourceCreateWithData(inputData as CFData, nil) else { return nil }

        if let passthrough = passthroughIfAlreadySafe(source: source, inputData: inputData, limits: limits) {
            return passthrough
        }

        guard let image = downsampledImage(source: source, maxPixelSize: limits.maxPixels) else { return nil }

        if isOpaque(image) {
            return encodeOpaqueLadder(source: source, firstAttempt: image, limits: limits)
        }

        if let pngResult = encodeAlphaLadder(source: source, limits: limits) {
            return pngResult
        }

        return encodeOpaqueLadder(source: source, firstAttempt: nil, limits: limits)
    }

    private static func passthroughIfAlreadySafe(source: CGImageSource, inputData: Data, limits: ImageUploadLimits) -> (data: Data, mimeType: String)? {
        guard let type = CGImageSourceGetType(source) as String? else { return nil }
        let mimeType: String
        if UTType(type) == .jpeg {
            mimeType = "image/jpeg"
        } else if UTType(type) == .png {
            mimeType = "image/png"
        } else {
            return nil
        }

        guard inputData.count <= limits.maxUploadBytes else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let widthNumber = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let heightNumber = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        let width = widthNumber.doubleValue
        let height = heightNumber.doubleValue
        guard width <= Double(limits.maxPixels), height <= Double(limits.maxPixels) else { return nil }

        return (inputData, mimeType)
    }

    private static func downsampledImage(source: CGImageSource, maxPixelSize: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func isOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            return false
        }
    }

    private static func encodeOpaqueLadder(source: CGImageSource, firstAttempt: CGImage?, limits: ImageUploadLimits) -> (data: Data, mimeType: String)? {
        var smallest: Data?
        var isFirstDimension = true

        for dimension in dimensionLadder(opaqueDimensionLadder, maxPixels: limits.maxPixels) {
            let image: CGImage?
            if isFirstDimension, let firstAttempt {
                image = firstAttempt
            } else {
                image = downsampledImage(source: source, maxPixelSize: dimension)
            }
            isFirstDimension = false

            guard let image else { continue }

            for quality in opaqueQualityLadder {
                guard let data = jpegData(from: image, quality: quality) else { continue }
                if smallest == nil || data.count < (smallest?.count ?? Int.max) {
                    smallest = data
                }
                if data.count <= limits.maxUploadBytes {
                    return (data, "image/jpeg")
                }
            }
        }

        guard let smallest else { return nil }
        return (smallest, "image/jpeg")
    }

    private static func encodeAlphaLadder(source: CGImageSource, limits: ImageUploadLimits) -> (data: Data, mimeType: String)? {
        for dimension in dimensionLadder(alphaDimensionLadder, maxPixels: limits.maxPixels) {
            guard let image = downsampledImage(source: source, maxPixelSize: dimension) else { continue }
            guard let data = pngData(from: image) else { continue }
            if data.count <= limits.maxUploadBytes {
                return (data, "image/png")
            }
        }
        return nil
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
