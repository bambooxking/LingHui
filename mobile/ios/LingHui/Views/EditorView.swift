import SwiftUI
import UIKit

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EditorViewModel

    init(sourceImage: UIImage, initialMode: EditorMode) {
        _viewModel = StateObject(
            wrappedValue: EditorViewModel(sourceImage: sourceImage, initialMode: initialMode)
        )
    }

    var body: some View {
        ZStack {
            LHTheme.mist.ignoresSafeArea()

            VStack(spacing: 14) {
                header
                ModeTabs(selectedMode: $viewModel.mode) { viewModel.selectMode($0) }
                    .padding(.horizontal, 16)

                EditorImageCanvas(
                    sourceImage: viewModel.sourceImage,
                    resultImage: viewModel.resultImage,
                    maskDocument: $viewModel.maskDocument,
                    maskTool: effectiveMaskTool,
                    brushDiameter: viewModel.brushDiameter,
                    isEditable: viewModel.isCanvasEditable,
                    interactionMode: $viewModel.canvasInteractionMode,
                    viewportResetToken: viewModel.viewportResetToken,
                    showOriginal: viewModel.isShowingOriginal,
                    showsComparison: viewModel.mode == .enhance && viewModel.resultImage != nil,
                    comparisonPosition: $viewModel.comparisonPosition,
                    showsRectangleRemovalControls:
                        viewModel.mode == .text
                        && viewModel.textMode == .automatic
                        && !viewModel.maskDocument.rectangles.isEmpty
                )
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 16)

                controlTray
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            if viewModel.isProcessing {
                processingOverlay
            }

            if let toast = viewModel.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 44)
                        .background(LHTheme.ink.opacity(0.94))
                        .clipShape(Capsule())
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation { viewModel.toast = nil }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden()
        .alert(item: $viewModel.error) { error in
            Alert(
                title: Text("处理未完成"),
                message: Text(error.message),
                dismissButton: .default(Text("知道了"))
            )
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LHTheme.ink)
                    .frame(width: 42, height: 42)
                    .background(LHTheme.paper)
                    .clipShape(Circle())
            }
            .accessibilityLabel("返回")

            VStack(spacing: 1) {
                Text(viewModel.mode.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
                Text(viewModel.resultImage == nil ? "在图片上完成选择" : "处理完成")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LHTheme.muted)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Button {
                    viewModel.restoreOriginal()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LHTheme.ink)
                        .frame(width: 42, height: 42)
                        .background(LHTheme.paper)
                        .clipShape(Circle())
                }
                .accessibilityLabel("恢复原图")

                Button {
                    viewModel.saveResult()
                } label: {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(viewModel.resultImage == nil ? LHTheme.muted : .white)
                        .frame(width: 42, height: 42)
                        .background(viewModel.resultImage == nil ? LHTheme.paper : LHTheme.successMint)
                        .clipShape(Circle())
                }
                .disabled(viewModel.resultImage == nil)
                .accessibilityLabel("保存到相册")
            }
        }
        .padding(.horizontal, 16)
    }

    private var effectiveMaskTool: MaskTool? {
        if viewModel.mode == .text {
            return viewModel.textMode == .manual ? .rectangle : nil
        }
        return viewModel.maskTool
    }

    @ViewBuilder
    private var controlTray: some View {
        VStack(spacing: 14) {
            if viewModel.resultImage == nil {
                switch viewModel.mode {
                case .erase:
                    eraseControls
                case .text:
                    textControls
                case .enhance:
                    enhanceControls
                }
                processButton
            } else {
                resultControls
            }
        }
        .lhCard(padding: 14)
    }

    private var eraseControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("选择方式")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LHTheme.muted)
                Spacer()
                Button("清除遮罩") { viewModel.clearMask() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.maskDocument.isEmpty ? LHTheme.muted : LHTheme.maskCoral)
                    .disabled(viewModel.maskDocument.isEmpty)
            }
            HStack(spacing: 6) {
                ForEach(MaskTool.allCases) { tool in
                    let isSelected = viewModel.maskTool == tool
                    Button {
                        viewModel.toggleMaskTool(tool)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tool.symbol)
                            Text(tool.title)
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : LHTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(isSelected ? LHTheme.repairBlue : LHTheme.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(isSelected ? "再次点击取消选择并拖动图片" : "点击选择此工具")
                }
            }
            if viewModel.maskTool == .brush {
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                    Slider(value: $viewModel.brushDiameter, in: 16...96)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 19))
                }
                .foregroundStyle(LHTheme.maskCoral)
                .accessibilityLabel("涂抹范围")
            }
        }
    }

    private var textControls: some View {
        VStack(spacing: 12) {
            CapsulePicker(
                options: TextRemovalMode.allCases,
                selection: $viewModel.textMode,
                title: \.title,
                symbol: nil
            )
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.textMode == .automatic ? "viewfinder" : "rectangle.dashed")
                    .foregroundStyle(LHTheme.repairBlue)
                Text(
                    viewModel.textMode == .automatic
                        ? "先识别文字并检查框选区域，再执行消除。"
                        : "在图片上拖出一个或多个长方形，框住要消除的文字。"
                )
                .font(.system(size: 12))
                .foregroundStyle(LHTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                if !viewModel.maskDocument.isEmpty {
                    Button("清除") { viewModel.clearMask() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LHTheme.maskCoral)
                }
            }

            if viewModel.textMode == .automatic {
                Button {
                    viewModel.recognizeText()
                } label: {
                    Label(
                        viewModel.maskDocument.rectangles.isEmpty ? "文字识别" : "重新识别",
                        systemImage: "text.viewfinder"
                    )
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(LHTheme.repairBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isProcessing)
                .accessibilityHint("检测图片中的文字并显示框选遮罩")
            }
        }
        .onChange(of: viewModel.textMode) { _, _ in
            viewModel.clearMask()
        }
    }

    private var enhanceControls: some View {
        VStack(spacing: 12) {
            HStack {
                Text("放大倍率")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LHTheme.muted)
                Spacer()
                Text("较大的照片会自动分块处理")
                    .font(.system(size: 11))
                    .foregroundStyle(LHTheme.muted)
            }
            HStack(spacing: 8) {
                ForEach([2, 4], id: \.self) { scale in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.enhanceScale = scale
                        }
                    } label: {
                        Text("\(scale)×")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(viewModel.enhanceScale == scale ? .white : LHTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                viewModel.enhanceScale == scale ? LHTheme.repairBlue : LHTheme.mist
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var processButton: some View {
        Button {
            viewModel.process()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: viewModel.mode == .enhance ? "sparkles" : "wand.and.rays")
                Text(actionTitle)
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(viewModel.canProcess ? LHTheme.ink : LHTheme.muted.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canProcess)
    }

    private var actionTitle: String {
        switch viewModel.mode {
        case .erase: "消除选中区域"
        case .text: viewModel.textMode == .automatic ? "消除识别文字" : "消除框选文字"
        case .enhance: "开始 \(viewModel.enhanceScale)× 修复"
        }
    }

    private var resultControls: some View {
        VStack(spacing: 13) {
            if viewModel.mode == .enhance {
                HStack(spacing: 12) {
                    Text("结果")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LHTheme.repairBlue)
                    ComparisonSlider(position: $viewModel.comparisonPosition)
                    Text("原图")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LHTheme.muted)
                }
                .accessibilityLabel("原图与修复结果对比")
            } else {
                HStack {
                    HoldToCompareButton(isShowingOriginal: $viewModel.isShowingOriginal)
                    Spacer()
                    Label("已完成", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(LHTheme.successMint)
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.restoreOriginal()
                } label: {
                    Text("恢复原图")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(LHTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(LHTheme.mist)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                Button {
                    viewModel.saveResult()
                } label: {
                    Label("保存图片", systemImage: "arrow.down.to.line.compact")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(LHTheme.successMint)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var processingOverlay: some View {
        ZStack {
            Color.black.opacity(0.36).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(LHTheme.hairline, lineWidth: 5)
                    Circle()
                        .trim(from: 0.08, to: 0.76)
                        .stroke(
                            LHTheme.repairBlue,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .rotationEffect(.degrees(viewModel.isProcessing ? 360 : 0))
                        .animation(
                            .linear(duration: 1).repeatForever(autoreverses: false),
                            value: viewModel.isProcessing
                        )
                }
                .frame(width: 54, height: 54)
                Text(viewModel.processingLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
                Text("模型正在本机运行，请稍候")
                    .font(.system(size: 12))
                    .foregroundStyle(LHTheme.muted)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
            .background(LHTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}
