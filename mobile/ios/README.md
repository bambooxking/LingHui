# LingHui iOS

灵绘是一个完全离线运行的 SwiftUI 图片修复应用，最低支持 iOS 17。

## 功能

- 涂抹消除：橡皮擦、可调笔刷范围、矩形框选、清除遮罩、按住对比原图。
- 文字消除：自动检测全部文字，或手动框选文字区域。
- 画质修复：2× / 4× 放大，支持滑杆对比原图。
- 黑白上色：使用 DDColor Tiny 为黑白照片生成自然色彩，支持滑杆对比原图。
- 从系统相册导入，处理结果保存回系统相册。

## 模型流程

- 涂抹/手动文字消除：`lama_dilated.mlmodelc`
- 画质修复：`Real-ESRGAN-x4plus.mlmodelc`，使用 128×128 分块推理
- 黑白上色：`DDColor_Tiny.mlmodelc` 以 512×512 灰阶 RGB 推理 LAB 色度通道，
  再与原图亮度通道合成并恢复至原始尺寸
- 自动文字消除：
  1. `PP-OCRv5_mobile_det.mlmodelc` 检测文字区域
  2. 将确认后的文字框合成一张完整遮罩
  3. `lama_dilated.mlmodelc` 一次性补全背景
模型通过 `project.yml` 引用仓库根目录的 `models/`，没有在 iOS 目录中复制一份。
暂未开放的 AI 生图实现保留在源码中，但不会参与 App 构建或启动链接。

## 构建

1. 使用 Xcode 打开 `LingHui.xcodeproj`。
2. 在 LingHui Target 的 Signing & Capabilities 中选择开发团队。
3. 选择 iOS 17 或更高版本的真机运行。

日常运行请选择 `LingHui` Scheme。它不会附加 LLDB、GPU 校验和运行时检查器，
可避免调试工具造成的启动页长时间停留。需要断点调试时切换到 `LingHui Debug` Scheme。

修改 `project.yml` 后，可重新生成工程：

```bash
xcodegen generate
```

命令行验证：

```bash
xcodebuild \
  -project LingHui.xcodeproj \
  -scheme LingHui \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

画质修复会把输入最长边限制到 1536 像素，以控制 4× 输出时的峰值内存。
