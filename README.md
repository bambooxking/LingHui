# LingHui

本地 NVIDIA GPU 图像工作台，支持水印/瑕疵涂抹消除与画质修复。针对 RTX 4070 Ti 16GB：模型首次使用时下载、按需加载，避免启动即占满显存。

## 功能

- 水印消除：浏览器画布支持**橡皮擦**（可调大小）、**圆形**、**长方形**遮罩。
  - `simple-lama-inpainting`：快速、无需提示词。
  - `diffusers/stable-diffusion-xl-1.0-inpainting-0.1`：纹理补全更好，支持提示词；首次下载约 7GB。
- 画质修复：`Real-ESRGAN`（通用超分）、`GFPGAN`（人像面部）。
- 可扩展：在 `app/services.py` 实现新的 `Adapter` 并注册到 `ADAPTERS` 即可增加算法。

## 安装与启动

要求 Python 3.10–3.12、[uv](https://docs.astral.sh/uv/) 和支持 CUDA 12.4 的 NVIDIA 驱动。在本目录运行：

```powershell
uv sync
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

访问 <http://127.0.0.1:8000>。需要局域网访问时将 `127.0.0.1` 改为 `0.0.0.0`。

确认 GPU 是否可用：

```powershell
uv run python -c "import torch; print(torch.cuda.is_available())"
```

默认依赖为 CUDA 12.4 版 PyTorch；若输出 `False`，请确认驱动或调整 `pyproject.toml` 中的 PyTorch 索引，然后再次运行 `uv sync`。

## 模型保存位置

模型下载固定保存于项目中，不会散落到用户目录：

- Hugging Face / SDXL：`models/huggingface/`
- Real-ESRGAN 与 GFPGAN：`models/weights/`

`models/` 已被 Git 忽略；删除该目录即可清理所有已下载模型。

## 使用方法

1. 上传图片。
2. 选择“水印消除”，使用橡皮擦、圆形或长方形标记待清除区域。橡皮擦大小可用滑块调整，遮罩宜只覆盖水印和少量边缘。
3. 选择 Simple LaMa 或 SDXL，点击“开始处理”；SDXL 可填写如 `clean blue sky` 的提示词。
4. 选择“画质修复”时，通用图片使用 Real-ESRGAN，人像使用 GFPGAN，选择倍率后处理。
5. 在页面预览结果，并点击“下载结果”。

模型会留在显存中以方便连续使用。需要释放时：

```powershell
curl.exe -X POST http://127.0.0.1:8000/api/models/sdxl/unload
```

将 `sdxl` 改为 `simple-lama`、`realesrgan` 或 `gfpgan` 可卸载相应模型。


## 目录

```text
app/main.py       FastAPI 接口
app/services.py   模型适配器、惰性加载和注册表
app/static/       无构建步骤的画布前端
models/           运行时下载模型（不提交）
```


## Q&A

Starting server at http://0.0.0.0:8000

如果 Windows 本机可用、但 Mac 不可用，再在 Windows 管理员 PowerShell 放行端口：

```powershell
New-NetFirewallRule -DisplayName "Inpainting Web 8000" `
  -Direction Inbound -Action Allow -Protocol TCP -L
```

## 移动端

### 模型来源

- [qualcomm/LaMa-Dilated](https://huggingface.co/qualcomm/LaMa-Dilated)
- [qualcomm/Real-ESRGAN-x4plus](https://huggingface.co/qualcomm/Real-ESRGAN-x4plus)
- [MobileSAM](https://github.com/john-rocky/CoreML-Models/tree/master#mobilesam)
- PaddleOCR v5
    - [PP-OCRv5_mobile_det](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_det_onnx)
    - [PP-OCRv5_mobile_rec](https://huggingface.co/PaddlePaddle/PP-OCRv5_mobile_rec_onnx)
