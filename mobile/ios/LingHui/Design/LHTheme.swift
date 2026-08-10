import SwiftUI
import UIKit

enum LHTheme {
    static let mist = Color.adaptive(light: 0xF4F6F8, dark: 0x0E121A)
    static let paper = Color.adaptive(light: 0xFFFFFF, dark: 0x181E29)
    static let ink = Color.adaptive(light: 0x172033, dark: 0xF4F7FC)
    static let repairBlue = Color.adaptive(light: 0x4169E1, dark: 0x7D9CFF)
    static let maskCoral = Color(hex: 0xFF6B5E)
    static let successMint = Color(hex: 0x28B487)
    static let muted = Color.adaptive(light: 0x687386, dark: 0x9BA6B8)
    static let hairline = Color.adaptive(light: 0xDDE3E8, dark: 0x2B3444)
    static let dawn = Color(hex: 0xFFB37A)
    static let twilight = Color(hex: 0x4356A8)

    static let canvasRadius: CGFloat = 28
    static let controlRadius: CGFloat = 18
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese
    case english

    var id: String { rawValue }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case day
    case night

    var id: String { rawValue }

    var colorScheme: ColorScheme {
        self == .day ? .light : .dark
    }
}

enum AppCopy {
    static func text(_ chinese: String, language: AppLanguage) -> String {
        guard language == .english else { return chinese }
        return english[chinese] ?? chinese
    }

    private static let english: [String: String] = [
        "首页": "Home",
        "设置": "Settings",
        "灵绘": "LingHui",
        "本地图片修复工具": "On-device photo repair",
        "今天想修复什么？": "What would you like to fix?",
        "选择一个工具，再从相册导入照片": "Choose a tool, then import a photo",
        "所有处理都在本机完成": "Everything is processed on this device",
        "功能": "Tools",
        "更多算法正在路上": "More tools are on the way",
        "涂抹消除": "Object eraser",
        "擦掉杂物，背景自然补全": "Brush away distractions and rebuild the background",
        "文字消除": "Text eraser",
        "自动识别或手动框选文字": "Detect text automatically or select it manually",
        "画质修复": "Photo enhance",
        "恢复纹理，放大依然清晰": "Recover detail and upscale with clarity",
        "黑白上色": "Photo colorizer",
        "为老照片还原自然色彩": "Bring natural color back to old photos",
        "无法导入照片": "Couldn’t import photo",
        "照片格式无法读取，请换一张照片重试。": "This photo format can’t be read. Try another photo.",
        "知道了": "OK",
        "语言": "Language",
        "中文": "Chinese",
        "英文": "English",
        "外观": "Appearance",
        "白天": "Day",
        "黑夜": "Night",
        "跟随你的创作节奏": "Match your editing rhythm",
        "白天模式清爽明亮，黑夜模式专注柔和。": "Day mode stays bright; night mode keeps the canvas calm.",
        "关于": "About",
        "版本": "Version",
        "离线处理": "On-device processing",
        "照片不会离开你的设备": "Your photos never leave this device",
        "返回": "Back",
        "恢复原图": "Restore original",
        "保存到相册": "Save to Photos",
        "在图片上完成选择": "Make a selection on the photo",
        "处理完成": "Complete",
        "处理未完成": "Processing incomplete",
        "选择方式": "Selection tool",
        "清除遮罩": "Clear mask",
        "清除": "Clear",
        "橡皮擦": "Brush",
        "长方形": "Rectangle",
        "再次点击取消选择并拖动图片": "Tap again to pan the photo",
        "点击选择此工具": "Tap to select this tool",
        "涂抹范围": "Brush size",
        "自动识别": "Auto detect",
        "手动框选": "Manual selection",
        "先识别文字并检查框选区域，再执行消除。": "Detect text, review the selected areas, then erase.",
        "在图片上拖出一个或多个长方形，框住要消除的文字。": "Draw one or more rectangles around the text to erase.",
        "文字识别": "Detect text",
        "重新识别": "Detect again",
        "检测图片中的文字并显示框选遮罩": "Detect text and show the selected regions",
        "放大倍率": "Upscale",
        "较大的照片会自动分块处理": "Large photos are processed in tiles",
        "消除选中区域": "Erase selected area",
        "消除识别文字": "Erase detected text",
        "消除框选文字": "Erase selected text",
        "开始修复": "Start enhancement",
        "开始上色": "Start colorizing",
        "自动分析画面，为黑白照片生成自然色彩。": "Analyze the scene and add natural color automatically.",
        "结果": "Result",
        "原图": "Original",
        "原图与修复结果对比": "Compare original and enhanced photo",
        "按住看原图": "Hold for original",
        "已完成": "Complete",
        "保存图片": "Save photo",
        "模型正在本机运行，请稍候": "The model is running on this device",
        "从首页选择其他功能": "Return home to choose another tool",
        "正在处理": "Processing",
        "已恢复原图": "Original restored",
        "正在识别文字": "Detecting text",
        "正在补全背景": "Rebuilding background",
        "正在合并框选并消除文字": "Merging selections and erasing text",
        "正在消除框选文字": "Erasing selected text",
        "正在逐块恢复细节": "Restoring detail tile by tile",
        "正在为照片上色": "Colorizing photo",
        "请先完成一次处理": "Process the photo first",
        "没有保存照片的权限，请在系统设置中允许灵绘添加照片。": "Photo access is off. Allow LingHui to add photos in Settings.",
        "已保存到相册": "Saved to Photos"
    ]
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    static func adaptive(light: UInt, dark: UInt) -> Color {
        Color(
            uiColor: UIColor { traits in
                UIColor(
                    Color(hex: traits.userInterfaceStyle == .dark ? dark : light)
                )
            }
        )
    }
}

extension View {
    func lhCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(LHTheme.paper)
            .clipShape(RoundedRectangle(cornerRadius: LHTheme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LHTheme.controlRadius, style: .continuous)
                    .stroke(LHTheme.hairline.opacity(0.8), lineWidth: 1)
            }
    }
}
