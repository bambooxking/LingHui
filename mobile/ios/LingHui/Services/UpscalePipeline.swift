import CoreML
import UIKit

struct UpscalePipeline {
    private let tileSize = 128
    private let tilePadding = 16
    private let modelScale = 4
    private let maxInputDimension: CGFloat = 1_536
    private var contentTileSize: Int { tileSize - tilePadding * 2 }

    func run(image: UIImage, scale requestedScale: Int) async throws -> UIImage {
        let scale = requestedScale == 2 ? 2 : 4
        let source = image.normalizedOrientation().resized(maxDimension: maxInputDimension)
        let sourceWidth = max(1, Int(source.size.width.rounded()))
        let sourceHeight = max(1, Int(source.size.height.rounded()))
        let targetSize = CGSize(width: sourceWidth * scale, height: sourceHeight * scale)
        var pieces: [(image: UIImage, destination: CGRect)] = []

        for y in stride(from: 0, to: sourceHeight, by: contentTileSize) {
            for x in stride(from: 0, to: sourceWidth, by: contentTileSize) {
                let validWidth = min(contentTileSize, sourceWidth - x)
                let validHeight = min(contentTileSize, sourceHeight - y)
                let tile = tileImage(
                    from: source,
                    origin: CGPoint(x: x - tilePadding, y: y - tilePadding)
                )
                let enhanced = try await processTile(tile)
                let validModelRect = CGRect(
                    x: tilePadding * modelScale,
                    y: tilePadding * modelScale,
                    width: validWidth * modelScale,
                    height: validHeight * modelScale
                )
                guard let cropped = enhanced.cgImage?.cropping(to: validModelRect) else {
                    throw ProcessingError(message: "超分块裁剪失败。")
                }
                pieces.append((
                    UIImage(cgImage: cropped),
                    CGRect(
                        x: x * scale,
                        y: y * scale,
                        width: validWidth * scale,
                        height: validHeight * scale
                    )
                ))
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            for piece in pieces {
                piece.image.draw(in: piece.destination)
            }
        }
    }

    private func processTile(_ tile: UIImage) async throws -> UIImage {
        let input = try ImageTensor.multiArray(
            from: tile,
            width: tileSize,
            height: tileSize,
            channelOrder: .rgb,
            normalization: .unitRGB
        )
        let output = try await ModelStore.shared.prediction(
            model: "Real-ESRGAN-x4plus",
            inputs: ["image": MLFeatureValue(multiArray: input)]
        )
        guard let array = output.featureValue(for: "clip_0")?.multiArrayValue else {
            throw ProcessingError(message: "画质修复模型没有返回图片。")
        }
        return try ImageTensor.image(
            from: array,
            width: tileSize * modelScale,
            height: tileSize * modelScale
        )
    }

    private func tileImage(
        from image: UIImage,
        origin: CGPoint
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: tileSize, height: tileSize),
            format: format
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
            image.draw(
                in: CGRect(
                    x: -origin.x,
                    y: -origin.y,
                    width: image.size.width,
                    height: image.size.height
                )
            )
        }
    }
}
