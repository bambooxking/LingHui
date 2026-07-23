import PhotosUI
import SwiftUI

struct RootView: View {
    @State private var selectedMode: EditorMode = .erase
    @State private var pickerItem: PhotosPickerItem?
    @State private var importedImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var importError: ProcessingError?

    var body: some View {
        NavigationStack {
            ZStack {
                LHTheme.mist.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 26) {
                        brandHeader
                        hero
                        modePicker
                        importButton
                        privacyNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(item: $importedImage) { image in
                EditorView(sourceImage: image, initialMode: selectedMode)
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                loadPhoto(newItem)
            }
            .alert(item: $importError) { error in
                Alert(
                    title: Text("无法导入照片"),
                    message: Text(error.message),
                    dismissButton: .default(Text("知道了"))
                )
            }
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LINGHUI")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(LHTheme.repairBlue)
                Text("灵绘")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
            }
            Spacer()
            ZStack {
                Circle().fill(LHTheme.ink)
                Image(systemName: "wand.and.stars.inverse")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
            .accessibilityHidden(true)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("把不需要的，\n留在画布之外。")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .tracking(-1.2)
                .foregroundStyle(LHTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Image(systemName: "iphone")
                Text("所有处理都在本机完成")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(LHTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modePicker: some View {
        VStack(spacing: 12) {
            ForEach(EditorMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 15) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(mode == selectedMode ? LHTheme.repairBlue : LHTheme.mist)
                            Image(systemName: mode.symbol)
                                .font(.system(size: 21, weight: .semibold))
                                .foregroundStyle(mode == selectedMode ? .white : LHTheme.ink)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(LHTheme.ink)
                            Text(mode.subtitle)
                                .font(.system(size: 13))
                                .foregroundStyle(LHTheme.muted)
                        }
                        Spacer()
                        Image(systemName: mode == selectedMode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(mode == selectedMode ? LHTheme.repairBlue : LHTheme.hairline)
                            .font(.system(size: 21))
                    }
                    .padding(14)
                    .background(LHTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                mode == selectedMode ? LHTheme.repairBlue.opacity(0.36) : LHTheme.hairline,
                                lineWidth: mode == selectedMode ? 1.5 : 1
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(mode.title)，\(mode.subtitle)")
            }
        }
    }

    private var importButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: 10) {
                if isLoadingPhoto {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo.badge.plus")
                }
                Text(isLoadingPhoto ? "正在读取照片" : "从相册选择照片")
                    .fontWeight(.semibold)
            }
            .font(.system(size: 17, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(LHTheme.ink)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .disabled(isLoadingPhoto)
    }

    private var privacyNote: some View {
        Text("照片不会上传，模型推理与导出都在设备端完成。")
            .font(.system(size: 12))
            .foregroundStyle(LHTheme.muted)
            .multilineTextAlignment(.center)
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        isLoadingPhoto = true
        Task {
            defer {
                Task { @MainActor in
                    isLoadingPhoto = false
                    pickerItem = nil
                }
            }
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)?.normalizedOrientation() else {
                    throw ProcessingError(message: "照片格式无法读取，请换一张照片重试。")
                }
                await MainActor.run {
                    importedImage = image
                }
            } catch {
                await MainActor.run {
                    importError = ProcessingError(message: error.localizedDescription)
                }
            }
        }
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

