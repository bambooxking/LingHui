import CoreML
import UIKit

struct TextRemovalResult {
    let image: UIImage
    let mask: UIImage
    let detectedRegionCount: Int
}

struct TextRemovalPipeline {
    private let inpainting = InpaintingPipeline()

    func detectTextRegions(in image: UIImage) async throws -> [CGRect] {
        let boxes = try await detectTextBoxes(in: image.normalizedOrientation())
        guard !boxes.isEmpty else {
            throw ProcessingError(message: "没有检测到文字，请切换到手动框选。")
        }
        return boxes
    }

    func run(image: UIImage, boxes: [CGRect]) async throws -> TextRemovalResult {
        let source = image.normalizedOrientation()
        guard !boxes.isEmpty else {
            throw ProcessingError(message: "请先识别文字或手动框选文字区域。")
        }

        // Text is not a single semantic object: MobileSAM often returns only parts of
        // glyphs, outlines, or shadows. Use every user-confirmed OCR rectangle as one
        // combined mask so automatic removal behaves exactly like manual selection.
        let mask = combinedBoxMask(boxes: boxes, imageSize: source.size)
        let result = try await inpainting.run(image: source, mask: mask)
        return TextRemovalResult(image: result, mask: mask, detectedRegionCount: boxes.count)
    }

    func runAutomatic(image: UIImage) async throws -> TextRemovalResult {
        let boxes = try await detectTextRegions(in: image)
        return try await run(image: image, boxes: boxes)
    }

    private func detectTextBoxes(in image: UIImage) async throws -> [CGRect] {
        let dimension = 960
        let input = try ImageTensor.multiArray(
            from: image,
            width: dimension,
            height: dimension,
            channelOrder: .bgr,
            normalization: .paddleBGR,
            contentMode: .scaleAspectFit,
            backgroundColor: .black
        )
        let output = try await ModelStore.shared.prediction(
            model: "PP-OCRv5_mobile_det",
            inputs: ["x": MLFeatureValue(multiArray: input)]
        )
        guard let map = output.featureValue(for: "var_2219")?.multiArrayValue else {
            throw ProcessingError(message: "文字检测模型没有返回热力图。")
        }

        let fitRect = ImageTensor.drawRect(
            imageSize: image.size,
            canvasSize: CGSize(width: dimension, height: dimension),
            contentMode: .scaleAspectFit
        )
        return connectedComponents(
            map: map,
            mapSize: dimension,
            fitRect: fitRect,
            threshold: 0.25
        )
    }

    private func connectedComponents(
        map: MLMultiArray,
        mapSize: Int,
        fitRect: CGRect,
        threshold: Float
    ) -> [CGRect] {
        let sampleStep = 2
        let gridSize = mapSize / sampleStep
        let values = map.dataPointer.bindMemory(to: Float.self, capacity: map.count)
        let strides = map.strides.map(\.intValue)
        var active = [Bool](repeating: false, count: gridSize * gridSize)
        var visited = [Bool](repeating: false, count: gridSize * gridSize)

        for gy in 0..<gridSize {
            for gx in 0..<gridSize {
                let x = gx * sampleStep
                let y = gy * sampleStep
                let index = y * strides[strides.count - 2] + x * strides[strides.count - 1]
                active[gy * gridSize + gx] = values[index] >= threshold
            }
        }

        var boxes: [CGRect] = []
        var stack: [Int] = []
        for start in 0..<active.count where active[start] && !visited[start] {
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            var minX = start % gridSize
            var maxX = minX
            var minY = start / gridSize
            var maxY = minY
            var area = 0

            while let current = stack.popLast() {
                area += 1
                let x = current % gridSize
                let y = current / gridSize
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)

                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && nx < gridSize && ny >= 0 && ny < gridSize {
                    let next = ny * gridSize + nx
                    if active[next] && !visited[next] {
                        visited[next] = true
                        stack.append(next)
                    }
                }
            }

            guard area >= 10 else { continue }
            let componentWidth = CGFloat((maxX - minX + 1) * sampleStep)
            let componentHeight = CGFloat((maxY - minY + 1) * sampleStep)
            let horizontalPadding = max(8, min(componentHeight * 0.35, 42))
            let verticalPadding = max(8, min(componentHeight * 0.30, 36))
            let pixelRect = CGRect(
                x: CGFloat(minX * sampleStep) - horizontalPadding,
                y: CGFloat(minY * sampleStep) - verticalPadding,
                width: componentWidth + horizontalPadding * 2,
                height: componentHeight + verticalPadding * 2
            )
            let normalized = CGRect(
                x: (pixelRect.minX - fitRect.minX) / fitRect.width,
                y: (pixelRect.minY - fitRect.minY) / fitRect.height,
                width: pixelRect.width / fitRect.width,
                height: pixelRect.height / fitRect.height
            ).clampedToUnitSquare()
            guard normalized.width > 0.006, normalized.height > 0.006 else { continue }
            boxes.append(normalized)
        }

        return mergeNearbyBoxes(boxes)
            .map(expandedRemovalBox)
            .sorted { $0.width * $0.height > $1.width * $1.height }
            .prefix(25)
            .map { $0 }
    }

    private func expandedRemovalBox(_ box: CGRect) -> CGRect {
        let horizontalMargin = max(0.018, min(box.height * 0.24, 0.045))
        let verticalMargin = max(0.016, min(box.height * 0.20, 0.036))
        return box
            .insetBy(dx: -horizontalMargin, dy: -verticalMargin)
            .clampedToUnitSquare()
    }

    private func mergeNearbyBoxes(_ boxes: [CGRect]) -> [CGRect] {
        var pending = boxes
        var merged: [CGRect] = []
        while let seed = pending.popLast() {
            var union = seed
            var didMerge = true
            while didMerge {
                didMerge = false
                for index in pending.indices.reversed() {
                    let expanded = union.insetBy(dx: -0.018, dy: -0.012)
                    if expanded.intersects(pending[index]) {
                        union = union.union(pending.remove(at: index))
                        didMerge = true
                    }
                }
            }
            merged.append(union)
        }
        return merged
    }

    private func refineMaskWithMobileSAM(
        image: UIImage,
        boxes: [CGRect]
    ) async throws -> UIImage {
        let prepared = prepareSAMImage(image)
        let encoderInput = try ImageTensor.multiArray(
            from: prepared.image,
            width: 1024,
            height: 1024,
            channelOrder: .rgb,
            normalization: .mobileSAM
        )
        let encoderOutput = try await ModelStore.shared.prediction(
            model: "mobile_sam_encoder",
            inputs: ["image": MLFeatureValue(multiArray: encoderInput)]
        )
        guard let imageEmbeddings = encoderOutput
            .featureValue(for: "image_embeddings")?
            .multiArrayValue else {
            throw ProcessingError(message: "MobileSAM 编码器没有返回特征。")
        }

        let promptEncoder = try SAMPromptEncoder.loadFromBundle()
        let samBoxes = boxes.map { box -> CGRect in
            CGRect(
                x: box.minX * prepared.contentSize.width,
                y: box.minY * prepared.contentSize.height,
                width: box.width * prepared.contentSize.width,
                height: box.height * prepared.contentSize.height
            )
        }

        var batchMasks: [UIImage] = []
        for batch in samBoxes.chunked(into: 5) {
            let prompts = try promptEncoder.inputs(for: batch)
            let output = try await ModelStore.shared.prediction(
                model: "mobile_sam_decoder",
                inputs: [
                    "image_embeddings": MLFeatureValue(multiArray: imageEmbeddings),
                    "sparse_embeddings": MLFeatureValue(multiArray: prompts.sparse),
                    "dense_embeddings": MLFeatureValue(multiArray: prompts.dense)
                ]
            )
            guard let masks = output.featureValue(for: "masks")?.multiArrayValue,
                  let iou = output.featureValue(for: "iou_predictions")?.multiArrayValue else {
                throw ProcessingError(message: "MobileSAM 解码器没有返回遮罩。")
            }
            batchMasks.append(try bestSAMMask(masks: masks, iou: iou))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let combined = UIGraphicsImageRenderer(
            size: CGSize(width: 256, height: 256),
            format: format
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            context.cgContext.setBlendMode(.lighten)
            for mask in batchMasks {
                mask.draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
            }
        }

        let cropSize = CGSize(
            width: max(1, prepared.contentSize.width / 4),
            height: max(1, prepared.contentSize.height / 4)
        )
        guard let cropped = combined.cgImage?.cropping(
            to: CGRect(origin: .zero, size: cropSize)
        ) else {
            throw ProcessingError(message: "MobileSAM 遮罩裁剪失败。")
        }
        return UIImage(cgImage: cropped).resized(to: image.size)
    }

    private func bestSAMMask(masks: MLMultiArray, iou: MLMultiArray) throws -> UIImage {
        let iouValues = iou.dataPointer.bindMemory(to: Float.self, capacity: iou.count)
        let bestChannel = (0..<3).max { iouValues[$0] < iouValues[$1] } ?? 0
        let maskValues = masks.dataPointer.bindMemory(to: Float.self, capacity: masks.count)
        let strides = masks.strides.map(\.intValue)
        var bytes = [UInt8](repeating: 255, count: 256 * 256 * 4)
        for y in 0..<256 {
            for x in 0..<256 {
                let source = bestChannel * strides[strides.count - 3]
                    + y * strides[strides.count - 2]
                    + x * strides[strides.count - 1]
                let white: UInt8 = maskValues[source] > 0 ? 255 : 0
                let target = (y * 256 + x) * 4
                bytes[target] = white
                bytes[target + 1] = white
                bytes[target + 2] = white
            }
        }
        return try ImageTensor.uiImage(rgbaBytes: bytes, width: 256, height: 256)
    }

    private func prepareSAMImage(_ image: UIImage) -> (image: UIImage, contentSize: CGSize) {
        let scale = min(1024 / image.size.width, 1024 / image.size.height)
        let contentSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let prepared = UIGraphicsImageRenderer(
            size: CGSize(width: 1024, height: 1024),
            format: format
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            image.draw(in: CGRect(origin: .zero, size: contentSize))
        }
        return (prepared, contentSize)
    }

    private func combinedBoxMask(boxes: [CGRect], imageSize: CGSize) -> UIImage {
        var document = MaskDocument()
        document.rectangles = boxes
        return document.renderedMask(size: imageSize)
    }
}

private struct SAMPromptWeights: Decodable {
    let gaussianMatrix: [[Float]]
    let pointEmbeddings: [[Float]]
    let noMaskEmbed: [Float]

    enum CodingKeys: String, CodingKey {
        case gaussianMatrix = "gaussian_matrix"
        case pointEmbeddings = "point_embeddings"
        case noMaskEmbed = "no_mask_embed"
    }
}

private struct SAMPromptEncoder {
    let weights: SAMPromptWeights

    static func loadFromBundle() throws -> SAMPromptEncoder {
        guard let url = Bundle.main.url(
            forResource: "mobile_sam_prompt_encoder_weights",
            withExtension: "json"
        ) else {
            throw ProcessingError(message: "缺少 MobileSAM prompt encoder 权重。")
        }
        let data = try Data(contentsOf: url)
        return SAMPromptEncoder(weights: try JSONDecoder().decode(SAMPromptWeights.self, from: data))
    }

    func inputs(for boxes: [CGRect]) throws -> (sparse: MLMultiArray, dense: MLMultiArray) {
        let tokenCount = boxes.count * 2
        let sparse = try MLMultiArray(
            shape: [1, NSNumber(value: tokenCount), 256],
            dataType: .float32
        )
        let sparseValues = sparse.dataPointer.bindMemory(to: Float.self, capacity: sparse.count)
        for (boxIndex, box) in boxes.enumerated() {
            let corners = [
                (CGPoint(x: box.minX, y: box.minY), 2),
                (CGPoint(x: box.maxX, y: box.maxY), 3)
            ]
            for (cornerIndex, item) in corners.enumerated() {
                let embedding = positionEmbedding(point: item.0)
                let token = boxIndex * 2 + cornerIndex
                for channel in 0..<256 {
                    sparseValues[token * 256 + channel] =
                        embedding[channel] + weights.pointEmbeddings[item.1][channel]
                }
            }
        }

        let dense = try MLMultiArray(shape: [1, 256, 64, 64], dataType: .float32)
        let denseValues = dense.dataPointer.bindMemory(to: Float.self, capacity: dense.count)
        let plane = 64 * 64
        for channel in 0..<256 {
            let value = weights.noMaskEmbed[channel]
            for pixel in 0..<plane {
                denseValues[channel * plane + pixel] = value
            }
        }
        return (sparse, dense)
    }

    private func positionEmbedding(point: CGPoint) -> [Float] {
        let x = Float((point.x + 0.5) / 1024.0) * 2 - 1
        let y = Float((point.y + 0.5) / 1024.0) * 2 - 1
        var projected = [Float](repeating: 0, count: 128)
        for index in 0..<128 {
            projected[index] = (
                x * weights.gaussianMatrix[0][index]
                    + y * weights.gaussianMatrix[1][index]
            ) * 2 * .pi
        }
        return projected.map(sin) + projected.map(cos)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private extension CGRect {
    func clampedToUnitSquare() -> CGRect {
        let minX = min(max(self.minX, 0), 1)
        let minY = min(max(self.minY, 0), 1)
        let maxX = min(max(self.maxX, 0), 1)
        let maxY = min(max(self.maxY, 0), 1)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
