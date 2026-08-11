import asyncio
import json
import time
import base64
import io
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .services import ADAPTERS, AlgorithmError, algorithms

app = FastAPI(title="Inpainting Web")
app.mount("/static", StaticFiles(directory="app/static"), name="static")
PROGRESS: dict[str, dict] = {}


def set_progress(job_id: str | None, message: str, *, done: bool = False, percent: int | None = None):
    if not job_id:
        return
    state = {"message": message, "done": done, "ts": time.time()}
    if percent is not None:
        state["percent"] = max(0, min(100, int(percent)))
    PROGRESS[job_id] = state

def decode_image(raw: str | bytes) -> Image.Image:
    try:
        if isinstance(raw, str):
            raw = raw.split(",", 1)[-1]
        elif b"," in raw:
            raw = raw.split(b",", 1)[1]
        return Image.open(io.BytesIO(base64.b64decode(raw))).convert("RGBA")
    except Exception as exc: raise HTTPException(400, "无效的图片或遮罩数据") from exc

def decode_mask(raw: str | bytes, size: tuple[int, int]) -> Image.Image:
    decoded = decode_image(raw)
    mask = decoded.getchannel("A") if decoded.mode == "RGBA" else decoded.convert("L")
    if mask.size != size:
        mask = mask.resize(size, Image.Resampling.NEAREST)
    return mask

def png(image):
    data = io.BytesIO(); image.save(data, "PNG")
    return Response(data.getvalue(), media_type="image/png", headers={"Content-Disposition": "attachment; filename=result.png"})

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
_ocr = None


def text_mask(image: Image.Image) -> Image.Image:
    global _ocr
    try:
        if _ocr is None:
            from paddleocr import PaddleOCR
            _ocr = PaddleOCR(use_angle_cls=False, lang="ch")
        result = _ocr.ocr(np.asarray(image.convert("RGB")), cls=False)
    except Exception as exc:
        raise AlgorithmError(f"无法加载或运行 PaddleOCR：{exc}") from exc
    mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(mask)
    for line in (result[0] if result else []):
        if len(line) != 2 or line[1][1] < 0.5:
            continue
        draw.polygon([tuple(map(float, point)) for point in line[0]], fill=255)
    if mask.getbbox():
        mask = mask.filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.GaussianBlur(3))
        mask = mask.point(lambda value: 255 if value > 8 else 0)
    return mask

def batch_images(directory: Path):
    return [path for path in directory.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES]

@app.get("/")
def home(): return FileResponse("app/static/index.html")

@app.get("/api/algorithms")
def get_algorithms(): return {"algorithms": algorithms()}


@app.get("/api/progress/{job_id}")
async def get_progress(job_id: str):
    async def events():
        last = None
        for _ in range(3600):
            state = PROGRESS.get(job_id, {"message": "等待任务开始…", "done": False, "percent": 0})
            payload = json.dumps(state, ensure_ascii=False)
            if payload != last:
                yield f"data: {payload}\n\n"
                last = payload
            if state.get("done"):
                break
            await asyncio.sleep(1)
    return StreamingResponse(events(), media_type="text/event-stream")
@app.post("/api/inpaint")
async def inpaint(image: Annotated[UploadFile, File()], mask: Annotated[str, Form()], model: Annotated[str, Form()], prompt: Annotated[str, Form()] = "", steps: Annotated[int, Form()] = 25, job_id: Annotated[str, Form()] = ""):
    adapter = ADAPTERS.get(model)
    if not adapter or adapter.task != "inpaint": raise HTTPException(400, "无效的消除模型")
    try:
        source = Image.open(io.BytesIO(await image.read())).convert("RGB")
        decoded_mask = decode_mask(mask, source.size)
        set_progress(job_id, "正在准备涂抹消除任务…", percent=3)
        if model == "sdxl":
            step_count = max(1, min(int(steps), 50))
            def on_step(step, step_total):
                percent = 8 + int(((step + 1) / max(1, step_total)) * 88)
                set_progress(job_id, f"SDXL 推理第 {step + 1}/{step_total} 步，正在重绘遮罩区域…", percent=percent)
            set_progress(job_id, f"SDXL 模型已选择，准备执行 {step_count} 步推理…", percent=5)
            result = adapter.run(source, mask=decoded_mask, prompt=prompt, steps=step_count, progress=on_step)
        else:
            set_progress(job_id, "LaMA 正在处理遮罩区域…", percent=35)
            result = adapter.run(source, mask=decoded_mask, prompt=prompt, steps=steps)
        set_progress(job_id, "处理完成，正在返回结果图…", done=True, percent=100)
        return png(result)
    except AlgorithmError as exc: raise HTTPException(503, str(exc)) from exc

@app.post("/api/restore")
async def restore(image: Annotated[UploadFile, File()], model: Annotated[str, Form()], scale: Annotated[float, Form()] = 2):
    adapter = ADAPTERS.get(model)
    if not adapter or adapter.task != "restore": raise HTTPException(400, "无效的修复模型")
    try: return png(adapter.run(Image.open(io.BytesIO(await image.read())), scale=scale))
    except AlgorithmError as exc: raise HTTPException(503, str(exc)) from exc

@app.post("/api/text-remove")
def text_remove(directory: Annotated[str, Form()], steps: Annotated[int, Form()] = 20, job_id: Annotated[str, Form()] = ""):
    source = Path(directory).expanduser()
    if not source.is_dir():
        raise HTTPException(400, "目录不存在或不可访问")
    images = batch_images(source)
    if not images:
        raise HTTPException(400, "目录中没有支持的图片")
    output = source / "text_removed"
    output.mkdir(exist_ok=True)
    adapter = ADAPTERS["sdxl"]
    completed, skipped, failures = 0, 0, []
    total = len(images)
    set_progress(job_id, f"准备处理 {total} 张图片，输出目录：{output}", percent=0)
    for index, path in enumerate(images, start=1):
        base_percent = int((index - 1) * 100 / total)
        try:
            set_progress(job_id, f"第 {index}/{total} 张：读取 {path.name}", percent=base_percent)
            with Image.open(path) as source_image:
                source_image = source_image.convert("RGB")
                set_progress(job_id, f"第 {index}/{total} 张：PaddleOCR 识别文字区域…", percent=base_percent)
                mask = text_mask(source_image)
                if mask.getbbox():
                    step_count = max(1, min(steps, 50))
                    def on_step(step, step_total, name=path.name, item=index, count=total):
                        item_progress = (step + 1) / max(1, step_total)
                        percent = int(((item - 1) + item_progress) * 100 / count)
                        set_progress(job_id, f"第 {item}/{count} 张：{name}，SDXL 推理第 {step + 1}/{step_total} 步", percent=percent)
                    result = adapter.run(
                        source_image,
                        mask=mask,
                        prompt="",
                        steps=step_count,
                        progress=on_step,
                    )
                    completed += 1
                    set_progress(job_id, f"第 {index}/{total} 张：已重绘 {path.name}，正在保存…", percent=int(index * 100 / total))
                else:
                    result = source_image
                    skipped += 1
                    set_progress(job_id, f"第 {index}/{total} 张：未识别到文字，跳过重绘并直接保存 {path.name}", percent=int(index * 100 / total))
                result.save(output / f"{path.stem}.png", "PNG")
        except AlgorithmError as exc:
            set_progress(job_id, f"失败：{path.name}: {exc}", done=True, percent=base_percent)
            raise HTTPException(503, str(exc)) from exc
        except Exception as exc:
            failures.append(f"{path.name}: {exc}")
            set_progress(job_id, f"第 {index}/{total} 张失败：{path.name}: {exc}", percent=int(index * 100 / total))
    set_progress(job_id, f"完成：已重绘 {completed} 张，跳过 {skipped} 张（无文字），失败 {len(failures)} 张。输出：{output}", done=True, percent=100)
    return {"output": str(output), "processed": completed, "no_text": skipped, "failures": failures}


@app.post("/api/restore-batch")
def restore_batch(
    directory: Annotated[str, Form()],
    scale: Annotated[int, Form()] = 4,
    job_id: Annotated[str, Form()] = "",
):
    source = Path(directory).expanduser()
    if not source.is_dir():
        raise HTTPException(400, "目录不存在或不可访问")
    if scale not in (2, 4):
        raise HTTPException(400, "批量画质修复仅支持 ×2 或 ×4")
    images = batch_images(source)
    if not images:
        raise HTTPException(400, "目录中没有支持的图片")

    output = source / f"quality_restored_x{scale}"
    output.mkdir(exist_ok=True)
    adapter = ADAPTERS["realesrgan"]
    completed, failures = 0, []
    total = len(images)
    set_progress(job_id, f"准备使用 Real-ESRGAN ×{scale} 处理 {total} 张图片…", percent=0)

    for index, path in enumerate(images, start=1):
        percent = int((index - 1) * 100 / total)
        try:
            set_progress(job_id, f"第 {index}/{total} 张：正在增强 {path.name}", percent=percent)
            with Image.open(path) as source_image:
                result = adapter.run(source_image.convert("RGB"), scale=scale)
                result.save(output / f"{path.stem}.png", "PNG")
            completed += 1
            set_progress(
                job_id,
                f"第 {index}/{total} 张完成：{path.name}",
                percent=int(index * 100 / total),
            )
        except AlgorithmError as exc:
            set_progress(job_id, f"模型运行失败：{exc}", done=True, percent=percent)
            raise HTTPException(503, str(exc)) from exc
        except Exception as exc:
            failures.append(f"{path.name}: {exc}")

    set_progress(
        job_id,
        f"完成：成功 {completed} 张，失败 {len(failures)} 张。输出：{output}",
        done=True,
        percent=100,
    )
    return {"output": str(output), "processed": completed, "failures": failures}

@app.post("/api/models/{model}/unload")
def unload(model: str):
    if model not in ADAPTERS: raise HTTPException(404, "模型不存在")
    ADAPTERS[model].unload(); return {"ok": True}



