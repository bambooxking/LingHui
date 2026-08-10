import CoreImage
import CoreML
import Foundation
import StableDiffusion
import UIKit

enum SDXLPreparationUpdate: Sendable {
    case loading
    case ready
}

actor SDXLModelManager {
    static let shared = SDXLModelManager()

    private let imageDimension = 768
    private var pipeline: StableDiffusionXLPipeline?

    func prepare(
        progress: @escaping @Sendable (SDXLPreparationUpdate) -> Void
    ) async throws {
        if pipeline != nil {
            progress(.ready)
            return
        }

        progress(.loading)
        let resourcesURL = try bundledResourcesURL()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let loadedPipeline = try StableDiffusionXLPipeline(
            resourcesAt: resourcesURL,
            configuration: configuration,
            reduceMemory: false
        )
        try loadedPipeline.loadResources()
        pipeline = loadedPipeline
        progress(.ready)
    }

    func generate(
        sourceImage: UIImage,
        mask: UIImage?,
        preset: AIGenerationPreset,
        progress: @escaping @Sendable (Double) -> Void
    ) throws -> UIImage {
        guard let pipeline else {
            throw ProcessingError(message: "SDXL 模型尚未准备完成。")
        }

        let source = sourceImage.normalizedOrientation()
        let prepared = squareInput(from: source)
        guard let startingImage = prepared.image.cgImage else {
            throw ProcessingError(message: "无法创建 SDXL 输入图片。")
        }

        var configuration = PipelineConfiguration(prompt: preset.prompt)
        configuration.negativePrompt = preset.negativePrompt
        configuration.startingImage = startingImage
        configuration.strength = preset.strength
        configuration.imageCount = 1
        configuration.stepCount = 20
        configuration.seed = UInt32.random(in: 0...UInt32.max)
        configuration.guidanceScale = 7.5
        configuration.schedulerType = .dpmSolverMultistepScheduler
        configuration.encoderScaleFactor = 0.13025
        configuration.decoderScaleFactor = 0.13025
        configuration.originalSize = Float32(imageDimension)
        configuration.targetSize = Float32(imageDimension)

        let outputs = try pipeline.generateImages(configuration: configuration) { update in
            let completed = Double(update.step + 1)
            progress(min(completed / Double(max(update.stepCount, 1)), 1))
            return true
        }
        guard let generatedCGImage = outputs.first ?? nil else {
            throw ProcessingError(message: "SDXL 没有生成可用图片。")
        }

        let generatedSquare = UIImage(cgImage: generatedCGImage)
        let generated = cropGeneratedImage(
            generatedSquare,
            contentRect: prepared.contentRect,
            outputSize: source.size
        )

        if preset.requiresMask {
            guard let mask else {
                throw ProcessingError(message: "请先涂抹或框选需要消除的区域。")
            }
            return try composite(
                generated: generated,
                over: source,
                using: mask.normalizedOrientation()
            )
        }
        return generated
    }

    private func bundledResourcesURL() throws -> URL {
        guard let directory = Bundle.main.url(
            forResource: "sdxl",
            withExtension: nil
        ) else {
            throw ProcessingError(
                message: "应用内未找到 SDXL 模型目录，请确认 models/sdxl 已加入 Copy Bundle Resources。"
            )
        }
        let required = [
            "TextEncoder.mlmodelc",
            "TextEncoder2.mlmodelc",
            "VAEDecoder.mlmodelc",
            "VAEEncoder.mlmodelc",
            "vocab.json",
            "merges.txt"
        ]
        let missing = required.filter {
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent($0).path
            )
        }
        guard missing.isEmpty else {
            throw ProcessingError(
                message: "本地 SDXL 模型不完整，缺少：\(missing.joined(separator: "、"))。"
            )
        }
        let hasUnet = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("Unet.mlmodelc").path
        )
        let hasChunkedUnet = FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("UnetChunk1.mlmodelc").path
        ) && FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("UnetChunk2.mlmodelc").path
        )
        guard hasUnet || hasChunkedUnet else {
            throw ProcessingError(message: "本地 SDXL 模型缺少 Unet 或 UnetChunk1/2。")
        }
        return directory
    }

    private func squareInput(from image: UIImage) -> (image: UIImage, contentRect: CGRect) {
        let canvasSize = CGSize(width: imageDimension, height: imageDimension)
        let contentRect = ImageTensor.drawRect(
            imageSize: image.size,
            canvasSize: canvasSize,
            contentMode: .scaleAspectFit
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: canvasSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvasSize))
            image.draw(in: contentRect)
        }
        return (result, contentRect)
    }

    private func cropGeneratedImage(
        _ image: UIImage,
        contentRect: CGRect,
        outputSize: CGSize
    ) -> UIImage {
        let scaleX = CGFloat(image.cgImage?.width ?? imageDimension) / CGFloat(imageDimension)
        let scaleY = CGFloat(image.cgImage?.height ?? imageDimension) / CGFloat(imageDimension)
        let pixelRect = CGRect(
            x: contentRect.minX * scaleX,
            y: contentRect.minY * scaleY,
            width: contentRect.width * scaleX,
            height: contentRect.height * scaleY
        ).integral
        guard let cropped = image.cgImage?.cropping(to: pixelRect) else {
            return image.resized(to: outputSize)
        }
        return UIImage(cgImage: cropped).resized(to: outputSize)
    }

    private func composite(
        generated: UIImage,
        over source: UIImage,
        using mask: UIImage
    ) throws -> UIImage {
        guard let generatedImage = CIImage(image: generated),
              let sourceImage = CIImage(image: source),
              let maskImage = CIImage(image: mask) else {
            throw ProcessingError(message: "无法合成 SDXL 生成结果。")
        }
        let extent = sourceImage.extent
        let softenedMask = maskImage
            .clampedToExtent()
            .applyingFilter(
                "CIGaussianBlur",
                parameters: [kCIInputRadiusKey: 2.0]
            )
            .cropped(to: extent)
        let output = generatedImage.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: sourceImage,
                kCIInputMaskImageKey: softenedMask
            ]
        )
        let context = CIContext(options: [.cacheIntermediates: true])
        guard let cgImage = context.createCGImage(output, from: extent) else {
            throw ProcessingError(message: "无法输出 SDXL 合成图片。")
        }
        return UIImage(cgImage: cgImage)
    }
}
