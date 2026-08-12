import json
import os
import shutil
import subprocess
import sys
import tempfile
from fractions import Fraction
from pathlib import Path

from .config import MODELS_DIR, ROOT
from .services import AlgorithmError


VIDEO_MODELS_DIR = MODELS_DIR / "video"
VIDEO_OUTPUT_DIR = ROOT / "outputs" / "videos"


def _setting(name: str, default: Path) -> Path:
    return Path(os.environ.get(name, default)).expanduser().resolve()


def _require(path: Path, description: str):
    if not path.exists():
        raise AlgorithmError(f"缺少{description}：{path}。请按 README 的“视频画质修复”章节安装视频模型。")


def _run(command: list[str], *, cwd: Path | None = None, env: dict | None = None):
    try:
        result = subprocess.run(command, cwd=cwd, env=env, check=True, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError as exc:
        raise AlgorithmError(f"未找到命令：{command[0]}") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stdout or "").strip()[-3000:]
        raise AlgorithmError(f"视频处理命令失败：{detail or '无错误输出'}") from exc
    return result.stdout


def _probe(input_path: Path) -> float:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        raise AlgorithmError("未找到 ffprobe，请先安装 FFmpeg。")
    output = _run([
        ffprobe, "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=avg_frame_rate", "-of", "json", str(input_path),
    ])
    streams = json.loads(output).get("streams", [])
    if not streams:
        raise AlgorithmError("上传文件中没有可解码的视频流。")
    try:
        fps = float(Fraction(streams[0]["avg_frame_rate"]))
    except (KeyError, ValueError, ZeroDivisionError) as exc:
        raise AlgorithmError("无法读取视频帧率。") from exc
    if fps <= 0:
        raise AlgorithmError("无法读取视频帧率。")
    return fps


def _python(name: str) -> str:
    return os.environ.get(name, sys.executable)


def _realbasicvsr(input_frames: Path, output_frames: Path):
    repository = _setting("REALBASICVSR_DIR", VIDEO_MODELS_DIR / "RealBasicVSR")
    script = repository / "inference_realbasicvsr.py"
    config = repository / "configs" / "realbasicvsr_x4.py"
    checkpoint = _setting("REALBASICVSR_CHECKPOINT", repository / "checkpoints" / "RealBasicVSR_x4.pth")
    _require(script, "RealBasicVSR 推理脚本")
    _require(config, "RealBasicVSR 配置")
    _require(checkpoint, "RealBasicVSR 权重")
    _run([
        _python("REALBASICVSR_PYTHON"), str(script), str(config), str(checkpoint),
        str(input_frames), str(output_frames), "--max_seq_len", "30",
    ], cwd=repository)


def _codeformer(input_frames: Path, output_frames: Path):
    repository = _setting("CODEFORMER_DIR", VIDEO_MODELS_DIR / "CodeFormer")
    script = repository / "inference_codeformer.py"
    _require(script, "CodeFormer 推理脚本")
    result_root = output_frames.parent / "codeformer-result"
    _run([
        _python("CODEFORMER_PYTHON"), str(script), "--input_path", str(input_frames),
        "--output_path", str(result_root), "--fidelity_weight", "0.7",
        "--upscale", "1", "--detection_model", "retinaface_mobile0.25",
    ], cwd=repository)
    restored = result_root / "final_results"
    output_frames.mkdir(parents=True, exist_ok=True)
    for frame in input_frames.glob("*.png"):
        candidate = restored / frame.name
        shutil.copy2(candidate if candidate.exists() else frame, output_frames / frame.name)


def _rife(input_frames: Path, output_frames: Path):
    repository = _setting("RIFE_DIR", VIDEO_MODELS_DIR / "Practical-RIFE")
    script = repository / "inference_video.py"
    model = _setting("RIFE_MODEL_DIR", repository / "train_log")
    _require(script, "RIFE 推理脚本")
    _require(model / "flownet.pkl", "RIFE 权重")
    work_dir = output_frames.parent / "rife-work"
    work_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PYTHONPATH"] = str(repository) + os.pathsep + env.get("PYTHONPATH", "")
    _run([
        _python("RIFE_PYTHON"), str(script), "--img", str(input_frames),
        "--model", str(model), "--multi", "2", "--png",
    ], cwd=work_dir, env=env)
    generated = work_dir / "vid_out"
    _require(generated, "RIFE 输出帧")
    shutil.move(str(generated), str(output_frames))


def process_video(input_path: Path, output_name: str, *, codeformer: bool, rife: bool, progress) -> Path:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise AlgorithmError("未找到 ffmpeg，请先安装 FFmpeg。")
    fps = _probe(input_path)
    VIDEO_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    output_path = VIDEO_OUTPUT_DIR / output_name
    with tempfile.TemporaryDirectory(prefix="linghui-video-") as temporary:
        work = Path(temporary)
        decoded = work / "decoded"
        enhanced = work / "realbasicvsr"
        decoded.mkdir()
        progress("FFmpeg 正在解码视频为逐帧 PNG…", 8)
        _run([ffmpeg, "-y", "-i", str(input_path), "-vsync", "0", str(decoded / "%08d.png")])
        progress("RealBasicVSR 正在进行时序画质修复…", 24)
        _realbasicvsr(decoded, enhanced)
        current = enhanced
        if codeformer:
            face_frames = work / "codeformer"
            progress("CodeFormer 正在检测并修复画面中的人脸…", 58)
            _codeformer(current, face_frames)
            current = face_frames
        if rife:
            interpolated = work / "rife"
            progress("RIFE 正在生成中间帧并将帧率提升 2 倍…", 76)
            _rife(current, interpolated)
            current = interpolated
            fps *= 2
            pattern = "%07d.png"
            start_number = "0"
        else:
            pattern = "%08d.png"
            start_number = "1"
        progress("FFmpeg 正在编码 MP4 并合并原始音频…", 90)
        _run([
            ffmpeg, "-y", "-framerate", f"{fps:.6f}", "-start_number", start_number,
            "-i", str(current / pattern), "-i", str(input_path), "-map", "0:v:0",
            "-map", "1:a?", "-c:v", "libx264", "-preset", "medium", "-crf", "18",
            "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest",
            "-movflags", "+faststart", str(output_path),
        ])
    return output_path
