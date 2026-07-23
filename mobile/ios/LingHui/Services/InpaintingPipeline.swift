import CoreML
import UIKit

struct InpaintingPipeline {
    func run(image: UIImage, mask: UIImage) async throws -> UIImage {
        let source = image.normalizedOrientation()
        let imageArray = try ImageTensor.multiArray(
            from: source,
            width: 512,
            height: 512,
            channelOrder: .rgb,
            normalization: .unitRGB
        )
        let maskArray = try ImageTensor.maskArray(from: mask, width: 512, height: 512)
        let output = try await ModelStore.shared.prediction(
            model: "lama_dilated",
            inputs: [
                "image": MLFeatureValue(multiArray: imageArray),
                "mask": MLFeatureValue(multiArray: maskArray)
            ]
        )
        guard let resultArray = output.featureValue(for: "var_1958")?.multiArrayValue else {
            throw ProcessingError(message: "消除模型没有返回图片。")
        }
        let result = try ImageTensor.image(from: resultArray, width: 512, height: 512)
        return result.resized(to: source.size)
    }
}
