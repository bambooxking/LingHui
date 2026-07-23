import CoreGraphics
import CoreML
import UIKit

enum ChannelOrder {
    case rgb
    case bgr
}

struct TensorNormalization {
    let scale: Float
    let mean: [Float]
    let standardDeviation: [Float]

    static let unitRGB = TensorNormalization(
        scale: 1.0 / 255.0,
        mean: [0, 0, 0],
        standardDeviation: [1, 1, 1]
    )

    static let paddleBGR = TensorNormalization(
        scale: 1.0 / 255.0,
        mean: [0.485, 0.456, 0.406],
        standardDeviation: [0.229, 0.224, 0.225]
    )

    static let mobileSAM = TensorNormalization(
        scale: 1.0 / 255.0,
        mean: [123.675 / 255.0, 116.28 / 255.0, 103.53 / 255.0],
        standardDeviation: [58.395 / 255.0, 57.12 / 255.0, 57.375 / 255.0]
    )
}

enum ImageTensor {
    static func multiArray(
        from image: UIImage,
        width: Int,
        height: Int,
        channelOrder: ChannelOrder = .rgb,
        normalization: TensorNormalization = .unitRGB,
        contentMode: UIView.ContentMode = .scaleToFill,
        backgroundColor: UIColor = .black
    ) throws -> MLMultiArray {
        let bytes = try rgbaBytes(
            from: image,
            width: width,
            height: height,
            contentMode: contentMode,
            backgroundColor: backgroundColor
        )
        let array = try MLMultiArray(
            shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let plane = width * height
        let sourceChannels = channelOrder == .rgb ? [0, 1, 2] : [2, 1, 0]

        for channel in 0..<3 {
            let sourceChannel = sourceChannels[channel]
            let mean = normalization.mean[channel]
            let std = normalization.standardDeviation[channel]
            let planeOffset = channel * plane
            for pixel in 0..<plane {
                let raw = Float(bytes[pixel * 4 + sourceChannel])
                pointer[planeOffset + pixel] = (raw * normalization.scale - mean) / std
            }
        }
        return array
    }

    static func maskArray(from mask: UIImage, width: Int, height: Int) throws -> MLMultiArray {
        let bytes = try rgbaBytes(
            from: mask,
            width: width,
            height: height,
            contentMode: .scaleToFill,
            backgroundColor: .black
        )
        let array = try MLMultiArray(
            shape: [1, 1, NSNumber(value: height), NSNumber(value: width)],
            dataType: .float32
        )
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        for pixel in 0..<(width * height) {
            pointer[pixel] = Float(bytes[pixel * 4]) / 255.0
        }
        return array
    }

    static func image(
        from array: MLMultiArray,
        width: Int,
        height: Int,
        channels: Int = 3,
        clamp: ClosedRange<Float> = 0...1
    ) throws -> UIImage {
        guard array.dataType == .float32 else {
            throw ProcessingError(message: "模型输出不是 Float32，无法生成图片。")
        }
        let values = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let strides = array.strides.map(\.intValue)
        guard strides.count >= 4 else {
            throw ProcessingError(message: "模型输出维度不正确。")
        }

        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                for channel in 0..<min(channels, 3) {
                    let index = channel * strides[strides.count - 3]
                        + y * strides[strides.count - 2]
                        + x * strides[strides.count - 1]
                    let value = min(max(values[index], clamp.lowerBound), clamp.upperBound)
                    bytes[pixel * 4 + channel] = UInt8((value * 255).rounded())
                }
            }
        }
        return try uiImage(rgbaBytes: bytes, width: width, height: height)
    }

    static func grayscaleImage(
        from array: MLMultiArray,
        width: Int,
        height: Int,
        threshold: Float? = nil
    ) throws -> UIImage {
        guard array.dataType == .float32 else {
            throw ProcessingError(message: "遮罩输出不是 Float32。")
        }
        let values = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let strides = array.strides.map(\.intValue)
        guard strides.count >= 4 else {
            throw ProcessingError(message: "遮罩输出维度不正确。")
        }

        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = y * strides[strides.count - 2] + x * strides[strides.count - 1]
                let raw = values[index]
                let normalized: Float
                if let threshold {
                    normalized = raw >= threshold ? 1 : 0
                } else {
                    normalized = min(max(raw, 0), 1)
                }
                let value = UInt8((normalized * 255).rounded())
                let pixel = (y * width + x) * 4
                bytes[pixel] = value
                bytes[pixel + 1] = value
                bytes[pixel + 2] = value
            }
        }
        return try uiImage(rgbaBytes: bytes, width: width, height: height)
    }

    static func rgbaBytes(
        from image: UIImage,
        width: Int,
        height: Int,
        contentMode: UIView.ContentMode,
        backgroundColor: UIColor
    ) throws -> [UInt8] {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let rendered = renderer.image { context in
            backgroundColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let target = drawRect(
                imageSize: image.size,
                canvasSize: CGSize(width: width, height: height),
                contentMode: contentMode
            )
            image.draw(in: target)
        }

        guard let cgImage = rendered.cgImage else {
            throw ProcessingError(message: "无法读取图片像素。")
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw ProcessingError(message: "无法创建图片像素缓冲区。")
        }
        // UIGraphicsImageRenderer has already normalized the image into a
        // top-to-bottom pixel buffer. Flipping this CGContext again reverses
        // tensor rows, which makes whole-image outputs upside down and tiled
        // outputs appear as vertically stacked strips.
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return bytes
    }

    static func uiImage(rgbaBytes: [UInt8], width: Int, height: Int) throws -> UIImage {
        let data = Data(rgbaBytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(
                    rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ProcessingError(message: "无法生成处理后的图片。")
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    static func drawRect(
        imageSize: CGSize,
        canvasSize: CGSize,
        contentMode: UIView.ContentMode
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: canvasSize)
        }
        if contentMode == .scaleAspectFit {
            let scale = min(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: (canvasSize.width - size.width) / 2,
                y: (canvasSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        if contentMode == .scaleAspectFill {
            let scale = max(canvasSize.width / imageSize.width, canvasSize.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: (canvasSize.width - size.width) / 2,
                y: (canvasSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        return CGRect(origin: .zero, size: canvasSize)
    }
}

extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up, scale == 1 {
            return self
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        return resized(to: CGSize(width: size.width * scale, height: size.height * scale))
    }
}

extension MaskDocument {
    func renderedMask(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.white.setFill()
            UIColor.white.setStroke()
            for rect in rectangles {
                let target = CGRect(
                    x: rect.minX * size.width,
                    y: rect.minY * size.height,
                    width: rect.width * size.width,
                    height: rect.height * size.height
                )
                context.cgContext.fill(target)
            }

            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            for stroke in strokes where !stroke.points.isEmpty {
                context.cgContext.setLineWidth(stroke.normalizedWidth * min(size.width, size.height))
                context.cgContext.beginPath()
                let start = CGPoint(
                    x: stroke.points[0].x * size.width,
                    y: stroke.points[0].y * size.height
                )
                context.cgContext.move(to: start)
                if stroke.points.count == 1 {
                    context.cgContext.addLine(to: CGPoint(x: start.x + 0.1, y: start.y + 0.1))
                } else {
                    for point in stroke.points.dropFirst() {
                        context.cgContext.addLine(
                            to: CGPoint(x: point.x * size.width, y: point.y * size.height)
                        )
                    }
                }
                context.cgContext.strokePath()
            }
        }
    }
}
