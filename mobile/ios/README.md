# LingHui iOS

灵绘是一个完全离线运行的 SwiftUI 图片修复应用，最低支持 iOS 17。

## 功能

- 涂抹消除：橡皮擦、可调笔刷范围、矩形框选、清除遮罩、按住对比原图。
- 文字消除：自动检测全部文字，或手动框选文字区域。
- 画质修复：2× / 4× 放大，支持滑杆对比原图。
- 从系统相册导入，处理结果保存回系统相册。

## 模型流程

- 涂抹/手动文字消除：`lama_dilated.mlmodelc`
- 画质修复：`Real-ESRGAN-x4plus.mlmodelc`，使用 128×128 分块推理
- 自动文字消除：
  1. `PP-OCRv5_mobile_det.mlmodelc` 检测文字区域
  2. `mobile_sam_encoder.mlmodelc` 编码图片
  3. Prompt Encoder JSON 将检测框转成 MobileSAM 提示
  4. `mobile_sam_decoder.mlmodelc` 优化遮罩边缘
  5. `lama_dilated.mlmodelc` 补全背景

模型通过 `project.yml` 引用仓库根目录的 `models/`，没有在 iOS 目录中复制一份。

## 构建

1. 使用 Xcode 打开 `LingHui.xcodeproj`。
2. 在 LingHui Target 的 Signing & Capabilities 中选择开发团队。
3. 选择 iOS 17 或更高版本的真机运行。

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
