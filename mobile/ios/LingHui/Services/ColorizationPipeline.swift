import CoreML
import UIKit

struct ColorizationPipeline {
    private let modelSize = 512
    private let maxOutputDimension: CGFloat = 4_096

    func run(image: UIImage) async throws -> UIImage {
        let source = image.normalizedOrientation().resized(maxDimension: maxOutputDimension)
        let modelInput = try grayscaleModelInput(from: source)
        let output = try await ModelStore.shared.prediction(
            model: "DDColor_Tiny",
            inputs: ["image": MLFeatureValue(multiArray: modelInput)]
        )
        guard let abChannels = output.featureValue(for: "ab_channels")?.multiArrayValue else {
            throw ProcessingError(message: "黑白上色模型没有返回颜色信息。")
        }
        return try compose(source: source, abChannels: abChannels)
    }

    private func grayscaleModelInput(from image: UIImage) throws -> MLMultiArray {
        let resized = image.resized(
            to: CGSize(width: modelSize, height: modelSize)
        )
        let sourceBytes = try ImageTensor.rgbaBytes(
            from: resized,
            width: modelSize,
            height: modelSize,
            contentMode: .scaleToFill,
            backgroundColor: .black
        )
        var grayscaleBytes = sourceBytes
        for pixel in 0..<(modelSize * modelSize) {
            let offset = pixel * 4
            let lab = rgbToLab(
                red: Float(sourceBytes[offset]) / 255,
                green: Float(sourceBytes[offset + 1]) / 255,
                blue: Float(sourceBytes[offset + 2]) / 255
            )
            let neutral = labToRGB(lightness: lab.lightness, a: 0, b: 0)
            grayscaleBytes[offset] = byte(neutral.red)
            grayscaleBytes[offset + 1] = byte(neutral.green)
            grayscaleBytes[offset + 2] = byte(neutral.blue)
            grayscaleBytes[offset + 3] = 255
        }

        let grayscaleImage = try ImageTensor.uiImage(
            rgbaBytes: grayscaleBytes,
            width: modelSize,
            height: modelSize
        )
        return try ImageTensor.multiArray(
            from: grayscaleImage,
            width: modelSize,
            height: modelSize,
            channelOrder: .rgb,
            normalization: .unitRGB
        )
    }

    private func compose(source: UIImage, abChannels: MLMultiArray) throws -> UIImage {
        guard abChannels.dataType == .float32,
              abChannels.shape.map(\.intValue) == [1, 2, modelSize, modelSize] else {
            throw ProcessingError(message: "黑白上色模型输出尺寸不正确。")
        }

        let width = max(1, Int(source.size.width.rounded()))
        let height = max(1, Int(source.size.height.rounded()))
        let sourceBytes = try ImageTensor.rgbaBytes(
            from: source,
            width: width,
            height: height,
            contentMode: .scaleToFill,
            backgroundColor: .black
        )
        let values = abChannels.dataPointer.bindMemory(
            to: Float.self,
            capacity: abChannels.count
        )
        let strides = abChannels.strides.map(\.intValue)
        var outputBytes = [UInt8](repeating: 255, count: width * height * 4)

        for y in 0..<height {
            let modelY = height == 1
                ? 0
                : Float(y) * Float(modelSize - 1) / Float(height - 1)
            for x in 0..<width {
                let modelX = width == 1
                    ? 0
                    : Float(x) * Float(modelSize - 1) / Float(width - 1)
                let predictedA = sample(
                    values: values,
                    strides: strides,
                    channel: 0,
                    x: modelX,
                    y: modelY
                )
                let predictedB = sample(
                    values: values,
                    strides: strides,
                    channel: 1,
                    x: modelX,
                    y: modelY
                )
                let offset = (y * width + x) * 4
                let originalLab = rgbToLab(
                    red: Float(sourceBytes[offset]) / 255,
                    green: Float(sourceBytes[offset + 1]) / 255,
                    blue: Float(sourceBytes[offset + 2]) / 255
                )
                let enhanced = enhancedChroma(a: predictedA, b: predictedB)
                let color = labToRGB(
                    lightness: originalLab.lightness,
                    a: enhanced.a,
                    b: enhanced.b
                )
                outputBytes[offset] = byte(color.red)
                outputBytes[offset + 1] = byte(color.green)
                outputBytes[offset + 2] = byte(color.blue)
                outputBytes[offset + 3] = 255
            }
        }
        return try ImageTensor.uiImage(rgbaBytes: outputBytes, width: width, height: height)
    }

    private func enhancedChroma(a: Float, b: Float) -> (a: Float, b: Float) {
        let chroma = hypot(a, b)
        guard chroma > 1.5 else { return (a, b) }

        // DDColor Tiny tends to be conservative in weakly colored regions.
        // Boost low chroma more than already vivid colors while preserving hue.
        let adaptiveScale = 1.28 + 0.32 * exp(-chroma / 12)
        let gamutSafeScale = min(adaptiveScale, 92 / chroma)
        return (a * gamutSafeScale, b * gamutSafeScale)
    }

    private func sample(
        values: UnsafePointer<Float>,
        strides: [Int],
        channel: Int,
        x: Float,
        y: Float
    ) -> Float {
        let x0 = min(max(Int(floor(x)), 0), modelSize - 1)
        let y0 = min(max(Int(floor(y)), 0), modelSize - 1)
        let x1 = min(x0 + 1, modelSize - 1)
        let y1 = min(y0 + 1, modelSize - 1)
        let dx = x - Float(x0)
        let dy = y - Float(y0)

        func value(_ sampleX: Int, _ sampleY: Int) -> Float {
            values[
                channel * strides[strides.count - 3]
                    + sampleY * strides[strides.count - 2]
                    + sampleX * strides[strides.count - 1]
            ]
        }

        let top = value(x0, y0) * (1 - dx) + value(x1, y0) * dx
        let bottom = value(x0, y1) * (1 - dx) + value(x1, y1) * dx
        return top * (1 - dy) + bottom * dy
    }

    private func rgbToLab(red: Float, green: Float, blue: Float) -> LabColor {
        let linearRed = srgbToLinear(red)
        let linearGreen = srgbToLinear(green)
        let linearBlue = srgbToLinear(blue)
        let x = (
            0.4124564 * linearRed + 0.3575761 * linearGreen + 0.1804375 * linearBlue
        ) / 0.95047
        let y = 0.2126729 * linearRed + 0.7151522 * linearGreen + 0.0721750 * linearBlue
        let z = (
            0.0193339 * linearRed + 0.1191920 * linearGreen + 0.9503041 * linearBlue
        ) / 1.08883
        let fx = labForward(x)
        let fy = labForward(y)
        let fz = labForward(z)
        return LabColor(
            lightness: 116 * fy - 16,
            a: 500 * (fx - fy),
            b: 200 * (fy - fz)
        )
    }

    private func labToRGB(lightness: Float, a: Float, b: Float) -> RGBColor {
        let fy = (lightness + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        let x = 0.95047 * labInverse(fx)
        let y = labInverse(fy)
        let z = 1.08883 * labInverse(fz)
        let red = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let green = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let blue = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return RGBColor(
            red: linearToSRGB(red),
            green: linearToSRGB(green),
            blue: linearToSRGB(blue)
        )
    }

    private func srgbToLinear(_ value: Float) -> Float {
        value <= 0.04045
            ? value / 12.92
            : pow((value + 0.055) / 1.055, 2.4)
    }

    private func linearToSRGB(_ value: Float) -> Float {
        let converted = value <= 0.0031308
            ? 12.92 * value
            : 1.055 * pow(max(value, 0), 1 / 2.4) - 0.055
        return min(max(converted, 0), 1)
    }

    private func labForward(_ value: Float) -> Float {
        let delta: Float = 6 / 29
        return value > delta * delta * delta
            ? pow(value, 1 / 3)
            : value / (3 * delta * delta) + 4 / 29
    }

    private func labInverse(_ value: Float) -> Float {
        let delta: Float = 6 / 29
        return value > delta
            ? value * value * value
            : 3 * delta * delta * (value - 4 / 29)
    }

    private func byte(_ value: Float) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }
}

private struct LabColor {
    let lightness: Float
    let a: Float
    let b: Float
}

private struct RGBColor {
    let red: Float
    let green: Float
    let blue: Float
}
