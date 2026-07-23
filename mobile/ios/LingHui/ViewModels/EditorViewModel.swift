import Photos
import SwiftUI
import UIKit

@MainActor
final class EditorViewModel: ObservableObject {
    let sourceImage: UIImage

    @Published var mode: EditorMode
    @Published var resultImage: UIImage?
    @Published var maskDocument = MaskDocument()
    @Published var maskTool: MaskTool? = .brush
    @Published var brushDiameter: CGFloat = 23
    @Published var textMode: TextRemovalMode = .automatic
    @Published var enhanceScale = 4
    @Published var comparisonPosition: CGFloat = 0.55
    @Published var isShowingOriginal = false
    @Published var canvasInteractionMode: CanvasInteractionMode = .edit
    @Published var viewportResetToken = 0
    @Published var isProcessing = false
    @Published var processingLabel = "正在处理"
    @Published var error: ProcessingError?
    @Published var toast: String?

    init(sourceImage: UIImage, initialMode: EditorMode) {
        self.sourceImage = sourceImage.normalizedOrientation()
        self.mode = initialMode
    }

    var canProcess: Bool {
        guard !isProcessing else { return false }
        switch mode {
        case .erase:
            return !maskDocument.isEmpty
        case .text:
            return !maskDocument.rectangles.isEmpty
        case .enhance:
            return true
        }
    }

    var isCanvasEditable: Bool {
        guard resultImage == nil else { return false }
        if mode == .erase { return maskTool != nil }
        return mode == .text && textMode == .manual
    }

    func selectMode(_ newMode: EditorMode) {
        guard mode != newMode else { return }
        mode = newMode
        resultImage = nil
        maskDocument.clear()
        isShowingOriginal = false
        comparisonPosition = 0.55
        canvasInteractionMode = defaultInteractionMode
        viewportResetToken += 1
    }

    func clearMask() {
        withAnimation(.snappy(duration: 0.2)) {
            maskDocument.clear()
        }
    }

    func toggleMaskTool(_ tool: MaskTool) {
        withAnimation(.snappy(duration: 0.2)) {
            if maskTool == tool {
                maskTool = nil
                canvasInteractionMode = .navigate
            } else {
                maskTool = tool
                canvasInteractionMode = .edit
            }
        }
    }

    func restoreOriginal() {
        withAnimation(.snappy(duration: 0.24)) {
            resultImage = nil
            maskDocument.clear()
            isShowingOriginal = false
            comparisonPosition = 0.55
            canvasInteractionMode = defaultInteractionMode
            viewportResetToken += 1
        }
        toast = "已恢复原图"
    }

    func recognizeText() {
        guard !isProcessing else { return }
        isProcessing = true
        processingLabel = "正在识别文字"
        toast = nil
        Task {
            defer { isProcessing = false }
            do {
                let boxes = try await TextRemovalPipeline().detectTextRegions(in: sourceImage)
                withAnimation(.snappy(duration: 0.24)) {
                    maskDocument.strokes.removeAll()
                    maskDocument.rectangles = boxes
                }
                toast = "识别到 \(boxes.count) 处文字，可确认后消除"
            } catch {
                self.error = ProcessingError(message: readableMessage(for: error))
            }
        }
    }

    func process() {
        guard canProcess else { return }
        isProcessing = true
        toast = nil
        Task {
            defer { isProcessing = false }
            do {
                switch mode {
                case .erase:
                    processingLabel = "正在补全背景"
                    let mask = maskDocument.renderedMask(size: sourceImage.size)
                    resultImage = try await InpaintingPipeline().run(
                        image: sourceImage,
                        mask: mask
                    )
                case .text:
                    if textMode == .automatic {
                        processingLabel = "正在合并框选并消除文字"
                        let output = try await TextRemovalPipeline().run(
                            image: sourceImage,
                            boxes: maskDocument.rectangles
                        )
                        resultImage = output.image
                        toast = "已处理 \(output.detectedRegionCount) 处文字区域"
                    } else {
                        processingLabel = "正在消除框选文字"
                        let mask = maskDocument.renderedMask(size: sourceImage.size)
                        resultImage = try await InpaintingPipeline().run(
                            image: sourceImage,
                            mask: mask
                        )
                    }
                case .enhance:
                    processingLabel = "正在逐块恢复细节"
                    resultImage = try await UpscalePipeline().run(
                        image: sourceImage,
                        scale: enhanceScale
                    )
                    comparisonPosition = 0.5
                }
            } catch {
                self.error = ProcessingError(message: readableMessage(for: error))
            }
        }
    }

    func saveResult() {
        guard let resultImage else {
            toast = "请先完成一次处理"
            return
        }
        Task {
            do {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    throw ProcessingError(message: "没有保存照片的权限，请在系统设置中允许灵绘添加照片。")
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: resultImage)
                }
                toast = "已保存到相册"
            } catch {
                self.error = ProcessingError(message: readableMessage(for: error))
            }
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let processing = error as? ProcessingError {
            return processing.message
        }
        return error.localizedDescription
    }

    private var defaultInteractionMode: CanvasInteractionMode {
        isCanvasEditable ? .edit : .navigate
    }
}
