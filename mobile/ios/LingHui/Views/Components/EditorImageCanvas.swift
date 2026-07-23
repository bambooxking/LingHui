import SwiftUI
import UIKit

struct EditorImageCanvas: View {
    let sourceImage: UIImage
    let resultImage: UIImage?
    @Binding var maskDocument: MaskDocument
    let maskTool: MaskTool?
    let brushDiameter: CGFloat
    let isEditable: Bool
    @Binding var interactionMode: CanvasInteractionMode
    let viewportResetToken: Int
    let showOriginal: Bool
    let showsComparison: Bool
    @Binding var comparisonPosition: CGFloat
    let showsRectangleRemovalControls: Bool

    @State private var isDrawingStroke = false
    @State private var rectangleStart: CGPoint?
    @State private var rectanglePreview: CGRect?
    @State private var zoomScale: CGFloat = 1
    @State private var settledZoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var settledPanOffset: CGSize = .zero
    @State private var comparisonDragStart: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let baseFrame = ImageTensor.drawRect(
                imageSize: sourceImage.size,
                canvasSize: proxy.size,
                contentMode: .scaleAspectFit
            )
            let imageFrame = transformedFrame(from: baseFrame)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: LHTheme.canvasRadius, style: .continuous)
                    .fill(Color.black.opacity(0.92))

                if showsComparison, let resultImage {
                    comparisonView(result: resultImage, frame: imageFrame)
                } else {
                    Image(uiImage: showOriginal ? sourceImage : (resultImage ?? sourceImage))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(x: imageFrame.midX, y: imageFrame.midY)
                }

                if resultImage == nil, !maskDocument.isEmpty || rectanglePreview != nil {
                    maskOverlay(frame: imageFrame)
                }

                if resultImage == nil, showsRectangleRemovalControls {
                    rectangleRemovalControls(frame: imageFrame, canvasSize: proxy.size)
                }

                if isEditable {
                    interactionButton
                        .padding(12)
                }
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: LHTheme.canvasRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LHTheme.canvasRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            }
            .gesture(canvasDragGesture(baseFrame: baseFrame))
            .simultaneousGesture(magnificationGesture(baseFrame: baseFrame))
            .onChange(of: viewportResetToken) { _, _ in
                resetViewport()
            }
            .onChange(of: isEditable) { _, editable in
                interactionMode = editable ? .edit : .navigate
            }
            .accessibilityLabel("图片编辑画布")
            .accessibilityHint(
                isEditable && interactionMode == .edit
                    ? "在图片上涂抹或框选；切换到移动后可拖动画面"
                    : "双指缩放，单指拖动画面"
            )
            .frame(width: bounds.width, height: bounds.height)
        }
    }

    private var interactionButton: some View {
        Button {
            interactionMode = interactionMode == .edit ? .navigate : .edit
            isDrawingStroke = false
            rectangleStart = nil
            rectanglePreview = nil
        } label: {
            Label(
                interactionMode == .edit ? "涂抹" : "移动",
                systemImage: interactionMode == .edit ? "pencil.tip" : "hand.draw.fill"
            )
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color.black.opacity(0.72))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("在编辑遮罩和拖动画面之间切换")
    }

    @ViewBuilder
    private func comparisonView(result: UIImage, frame: CGRect) -> some View {
        let dividerX = frame.width * comparisonPosition

        ZStack(alignment: .leading) {
            Image(uiImage: sourceImage)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.width, height: frame.height)

            Image(uiImage: result)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .mask(alignment: .leading) {
                    Rectangle()
                        .frame(width: max(0, frame.width * comparisonPosition))
                }

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: frame.height)
                .offset(x: dividerX - 1)

            ZStack {
                Circle().fill(.white)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(LHTheme.ink)
            }
            .frame(width: 28, height: 28)
            .offset(x: dividerX - 14)

            Color.clear
                .frame(width: 44, height: frame.height)
                .contentShape(Rectangle())
                .offset(x: dividerX - 22)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if comparisonDragStart == nil {
                                comparisonDragStart = comparisonPosition
                            }
                            comparisonPosition = min(
                                max(
                                    (comparisonDragStart ?? comparisonPosition)
                                        + value.translation.width / frame.width,
                                    0
                                ),
                                1
                            )
                        }
                        .onEnded { _ in
                            comparisonDragStart = nil
                        }
                )
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func maskOverlay(frame: CGRect) -> some View {
        Canvas { context, _ in
            for rectangle in maskDocument.rectangles {
                drawRectangle(rectangle, in: frame, context: &context, opacity: 0.52)
            }

            for stroke in maskDocument.strokes where !stroke.points.isEmpty {
                var path = Path()
                let first = pointInFrame(stroke.points[0], frame: frame)
                path.move(to: first)
                if stroke.points.count == 1 {
                    path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
                } else {
                    for point in stroke.points.dropFirst() {
                        path.addLine(to: pointInFrame(point, frame: frame))
                    }
                }
                context.stroke(
                    path,
                    with: .color(LHTheme.maskCoral.opacity(0.68)),
                    style: StrokeStyle(
                        lineWidth: stroke.normalizedWidth * min(frame.width, frame.height),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            if let rectanglePreview {
                drawRectangle(rectanglePreview, in: frame, context: &context, opacity: 0.36)
            }
        }
        .allowsHitTesting(false)
    }

    private func rectangleRemovalControls(frame: CGRect, canvasSize: CGSize) -> some View {
        ForEach(Array(maskDocument.rectangles.enumerated()), id: \.offset) { item in
            let rectangle = item.element
            let buttonRadius: CGFloat = 13
            let corner = CGPoint(
                x: frame.minX + rectangle.maxX * frame.width,
                y: frame.minY + rectangle.minY * frame.height
            )
            let position = CGPoint(
                x: min(max(corner.x, buttonRadius), canvasSize.width - buttonRadius),
                y: min(max(corner.y, buttonRadius), canvasSize.height - buttonRadius)
            )

            Button {
                guard let index = maskDocument.rectangles.firstIndex(of: rectangle) else { return }
                withAnimation(.snappy(duration: 0.18)) {
                    _ = maskDocument.rectangles.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: buttonRadius * 2, height: buttonRadius * 2)
                    .background(LHTheme.maskCoral)
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white, lineWidth: 2)
                    }
                    .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .position(position)
            .accessibilityLabel("移除此文字框")
        }
    }

    private func drawRectangle(
        _ rectangle: CGRect,
        in frame: CGRect,
        context: inout GraphicsContext,
        opacity: Double
    ) {
        let pathRect = CGRect(
            x: frame.minX + rectangle.minX * frame.width,
            y: frame.minY + rectangle.minY * frame.height,
            width: rectangle.width * frame.width,
            height: rectangle.height * frame.height
        )
        context.fill(
            Path(roundedRect: pathRect, cornerRadius: 4),
            with: .color(LHTheme.maskCoral.opacity(opacity))
        )
        context.stroke(
            Path(roundedRect: pathRect, cornerRadius: 4),
            with: .color(.white.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
        )
    }

    private func canvasDragGesture(baseFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: interactionMode == .edit && isEditable ? 0 : 4)
            .onChanged { value in
                if interactionMode == .navigate || !isEditable || maskTool == nil {
                    panOffset = clampedOffset(
                        CGSize(
                            width: settledPanOffset.width + value.translation.width,
                            height: settledPanOffset.height + value.translation.height
                        ),
                        baseFrame: baseFrame,
                        scale: zoomScale
                    )
                    return
                }

                guard let maskTool else { return }
                switch maskTool {
                case .brush:
                    let imageFrame = transformedFrame(from: baseFrame)
                    guard let normalized = normalizedPoint(value.location, frame: imageFrame) else {
                        return
                    }
                    if !isDrawingStroke {
                        isDrawingStroke = true
                        maskDocument.strokes.append(
                            MaskStroke(
                                points: [normalized],
                                normalizedWidth: brushDiameter / min(imageFrame.width, imageFrame.height)
                            )
                        )
                    } else if !maskDocument.strokes.isEmpty {
                        maskDocument.strokes[maskDocument.strokes.count - 1].points.append(normalized)
                    }
                case .rectangle:
                    let imageFrame = transformedFrame(from: baseFrame)
                    if rectangleStart == nil {
                        guard let start = normalizedPoint(value.location, frame: imageFrame) else {
                            return
                        }
                        rectangleStart = start
                    }
                    if let rectangleStart {
                        let normalized = clampedNormalizedPoint(
                            value.location,
                            frame: imageFrame
                        )
                        rectanglePreview = CGRect(
                            x: min(rectangleStart.x, normalized.x),
                            y: min(rectangleStart.y, normalized.y),
                            width: abs(normalized.x - rectangleStart.x),
                            height: abs(normalized.y - rectangleStart.y)
                        )
                    }
                }
            }
            .onEnded { value in
                if interactionMode == .navigate || !isEditable || maskTool == nil {
                    settledPanOffset = panOffset
                    return
                }

                defer {
                    isDrawingStroke = false
                    rectangleStart = nil
                    rectanglePreview = nil
                }
                let imageFrame = transformedFrame(from: baseFrame)
                guard maskTool == .rectangle,
                      let start = rectangleStart else {
                    return
                }
                let end = clampedNormalizedPoint(value.location, frame: imageFrame)
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if rect.width > 0.008, rect.height > 0.008 {
                    maskDocument.rectangles.append(rect)
                }
            }
    }

    private func magnificationGesture(baseFrame: CGRect) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(max(settledZoomScale * value, 1), 6)
                panOffset = clampedOffset(panOffset, baseFrame: baseFrame, scale: zoomScale)
            }
            .onEnded { _ in
                settledZoomScale = zoomScale
                panOffset = clampedOffset(panOffset, baseFrame: baseFrame, scale: zoomScale)
                settledPanOffset = panOffset
            }
    }

    private func transformedFrame(from baseFrame: CGRect) -> CGRect {
        CGRect(
            x: baseFrame.midX - baseFrame.width * zoomScale / 2 + panOffset.width,
            y: baseFrame.midY - baseFrame.height * zoomScale / 2 + panOffset.height,
            width: baseFrame.width * zoomScale,
            height: baseFrame.height * zoomScale
        )
    }

    private func clampedOffset(_ offset: CGSize, baseFrame: CGRect, scale: CGFloat) -> CGSize {
        guard scale > 1 else { return .zero }
        let maxX = max(0, baseFrame.width * (scale - 1) / 2)
        let maxY = max(0, baseFrame.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func resetViewport() {
        zoomScale = 1
        settledZoomScale = 1
        panOffset = .zero
        settledPanOffset = .zero
        isDrawingStroke = false
        rectangleStart = nil
        rectanglePreview = nil
    }

    private func normalizedPoint(_ point: CGPoint, frame: CGRect) -> CGPoint? {
        guard frame.contains(point) else { return nil }
        return clampedNormalizedPoint(point, frame: frame)
    }

    private func clampedNormalizedPoint(_ point: CGPoint, frame: CGRect) -> CGPoint {
        return CGPoint(
            x: min(max((point.x - frame.minX) / frame.width, 0), 1),
            y: min(max((point.y - frame.minY) / frame.height, 0), 1)
        )
    }

    private func pointInFrame(_ point: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.minX + point.x * frame.width,
            y: frame.minY + point.y * frame.height
        )
    }
}
