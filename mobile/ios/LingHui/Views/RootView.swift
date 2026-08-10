import PhotosUI
import SwiftUI

struct RootView: View {
    @AppStorage("appLanguage") private var languageValue = AppLanguage.chinese.rawValue
    @AppStorage("appAppearance") private var appearanceValue = AppAppearance.day.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageValue) ?? .chinese
    }

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceValue) ?? .day
    }

    var body: some View {
        TabView {
            HomeFlow(language: language, appearance: appearance)
                .tabItem {
                    Label(
                        AppCopy.text("首页", language: language),
                        systemImage: "square.grid.2x2.fill"
                    )
                }

            SettingsView()
                .tabItem {
                    Label(
                        AppCopy.text("设置", language: language),
                        systemImage: "gearshape.fill"
                    )
                }
        }
        .tint(LHTheme.repairBlue)
        .preferredColorScheme(appearance.colorScheme)
    }
}

private struct HomeFlow: View {
    let language: AppLanguage
    let appearance: AppAppearance

    @State private var selectedMode: EditorMode = .erase
    @State private var pickerItem: PhotosPickerItem?
    @State private var importedImage: UIImage?
    @State private var isPhotoPickerPresented = false
    @State private var isLoadingPhoto = false
    @State private var importError: ProcessingError?

    var body: some View {
        NavigationStack {
            ZStack {
                LHTheme.mist.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        brandHeader
                        hero
                        featureSection
                        privacyNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationDestination(item: $importedImage) { image in
                EditorView(sourceImage: image, initialMode: selectedMode)
                    .toolbar(.hidden, for: .tabBar)
            }
            .photosPicker(
                isPresented: $isPhotoPickerPresented,
                selection: $pickerItem,
                matching: .images
            )
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                loadPhoto(newItem)
            }
            .alert(item: $importError) { error in
                Alert(
                    title: Text(copy("无法导入照片")),
                    message: Text(error.message),
                    dismissButton: .default(Text(copy("知道了")))
                )
            }
        }
    }

    private var brandHeader: some View {
        HStack {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LHTheme.ink)
                    Image(systemName: "wand.and.stars.inverse")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(LHTheme.paper)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 1) {
                    Text(copy("灵绘"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(LHTheme.ink)
                    Text(copy("本地图片修复工具"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LHTheme.muted)
                }
            }
            Spacer()
            if isLoadingPhoto {
                ProgressView()
                    .tint(LHTheme.repairBlue)
                    .frame(width: 42, height: 42)
                    .background(LHTheme.paper)
                    .clipShape(Circle())
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: appearance == .day
                            ? [Color(hex: 0xE9EFFF), Color(hex: 0xFFE9D7)]
                            : [Color(hex: 0x28345D), Color(hex: 0x3A274B)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(LHTheme.paper.opacity(0.42))
                .frame(width: 150, height: 150)
                .offset(x: 245, y: -54)

            Image(systemName: appearance == .day ? "sun.max.fill" : "moon.stars.fill")
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(appearance == .day ? LHTheme.dawn : Color(hex: 0xB9C8FF))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(24)

            VStack(alignment: .leading, spacing: 8) {
                Text(copy("今天想修复什么？"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(LHTheme.ink)
                Text(copy("选择一个工具，再从相册导入照片"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LHTheme.muted)
            }
            .padding(24)
        }
        .frame(height: 184)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var featureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(copy("功能"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
                Spacer()
                Text(copy("更多算法正在路上"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LHTheme.muted)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(EditorMode.homeModes) { mode in
                    FeatureCard(mode: mode, language: language) {
                        selectedMode = mode
                        isPhotoPickerPresented = true
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        Label(
            copy("所有处理都在本机完成"),
            systemImage: "lock.shield.fill"
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(LHTheme.muted)
        .frame(maxWidth: .infinity)
    }

    private func copy(_ chinese: String) -> String {
        AppCopy.text(chinese, language: language)
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
                    throw ProcessingError(message: copy("照片格式无法读取，请换一张照片重试。"))
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

private struct FeatureCard: View {
    let mode: EditorMode
    let language: AppLanguage
    let action: () -> Void

    private var tint: Color {
        switch mode {
        case .erase: Color(hex: 0xFF775F)
        case .text: Color(hex: 0x4D78E8)
        case .enhance: Color(hex: 0x22A983)
        case .colorize: Color(hex: 0xD45496)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(tint.opacity(0.14))
                        Image(systemName: mode.symbol)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: 52, height: 52)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(LHTheme.muted)
                        .frame(width: 28, height: 28)
                        .background(LHTheme.mist)
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.title(for: language))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(LHTheme.ink)
                    Text(mode.subtitle(for: language))
                        .font(.system(size: 12))
                        .foregroundStyle(LHTheme.muted)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 158, alignment: .leading)
            .background(LHTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LHTheme.hairline.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(mode.subtitle(for: language))
    }
}

private struct SettingsView: View {
    @AppStorage("appLanguage") private var languageValue = AppLanguage.chinese.rawValue
    @AppStorage("appAppearance") private var appearanceValue = AppAppearance.day.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: languageValue) ?? .chinese
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LHTheme.mist.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        appearancePreview
                        settingSection(title: copy("语言")) {
                            optionRow(
                                title: copy("中文"),
                                symbol: "character.book.closed",
                                selected: languageValue == AppLanguage.chinese.rawValue
                            ) {
                                languageValue = AppLanguage.chinese.rawValue
                            }
                            Divider().overlay(LHTheme.hairline)
                            optionRow(
                                title: copy("英文"),
                                symbol: "textformat.abc",
                                selected: languageValue == AppLanguage.english.rawValue
                            ) {
                                languageValue = AppLanguage.english.rawValue
                            }
                        }

                        settingSection(title: copy("外观")) {
                            optionRow(
                                title: copy("白天"),
                                symbol: "sun.max.fill",
                                selected: appearanceValue == AppAppearance.day.rawValue
                            ) {
                                appearanceValue = AppAppearance.day.rawValue
                            }
                            Divider().overlay(LHTheme.hairline)
                            optionRow(
                                title: copy("黑夜"),
                                symbol: "moon.stars.fill",
                                selected: appearanceValue == AppAppearance.night.rawValue
                            ) {
                                appearanceValue = AppAppearance.night.rawValue
                            }
                        }

                        settingSection(title: copy("关于")) {
                            infoRow(title: copy("版本"), value: appVersion)
                            Divider().overlay(LHTheme.hairline)
                            infoRow(title: copy("离线处理"), value: copy("照片不会离开你的设备"))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(copy("设置"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var appearancePreview: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [LHTheme.twilight, LHTheme.dawn],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: appearanceValue == AppAppearance.day.rawValue
                    ? "sun.max.fill"
                    : "moon.stars.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 5) {
                Text(copy("跟随你的创作节奏"))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
                Text(copy("白天模式清爽明亮，黑夜模式专注柔和。"))
                    .font(.system(size: 12))
                    .foregroundStyle(LHTheme.muted)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LHTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func settingSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(LHTheme.muted)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 16)
            .background(LHTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func optionRow(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selected ? LHTheme.repairBlue : LHTheme.muted)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(LHTheme.ink)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? LHTheme.repairBlue : LHTheme.hairline)
            }
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(LHTheme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(LHTheme.muted)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 52)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func copy(_ chinese: String) -> String {
        AppCopy.text(chinese, language: language)
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
