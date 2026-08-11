"""Lazy-loaded algorithm adapters. Add a class here to expose a new algorithm."""
import gc
import os
from abc import ABC, abstractmethod
from pathlib import Path

import numpy as np
import torch
from PIL import Image

from .config import HF_HOME, MODELS_DIR, WEIGHTS_DIR

os.environ.setdefault("HF_HOME", str(HF_HOME))
os.environ.setdefault("HUGGINGFACE_HUB_CACHE", str(HF_HOME / "hub"))
torch.hub.set_dir(str(MODELS_DIR / "torch-hub"))


class AlgorithmError(RuntimeError):
    pass


def ensure_torchvision_functional_tensor():
    import sys
    import types
    from torchvision.transforms.functional import rgb_to_grayscale

    compatibility = types.ModuleType("torchvision.transforms.functional_tensor")
    compatibility.rgb_to_grayscale = rgb_to_grayscale
    sys.modules.setdefault("torchvision.transforms.functional_tensor", compatibility)


class Adapter(ABC):
    title: str
    task: str
    _model = None

    def unload(self):
        self._model = None
        gc.collect()
        if torch.cuda.is_available():
            torch.cuda.empty_cache()

    @abstractmethod
    def run(self, image: Image.Image, **options) -> Image.Image: ...


class SimpleLama(Adapter):
    title, task = "simple-lama-inpainting", "inpaint"

    def run(self, image, *, mask, **_):
        if self._model is None:
            try:
                from simple_lama_inpainting import SimpleLama
                self._model = SimpleLama()
            except Exception as exc:
                raise AlgorithmError(f"无法加载 Simple LaMa：{exc}") from exc
        return self._model(image.convert("RGB"), mask.convert("L"))


class SDXLInpaint(Adapter):
    title, task = "SDXL Inpainting 0.1", "inpaint"
    model_id = "diffusers/stable-diffusion-xl-1.0-inpainting-0.1"
    # Describe the desired pixels instead of mentioning what should be removed.
    # Words such as "text" and "watermark" in the positive prompt can make a
    # diffusion model draw those concepts inside the masked area.
    default_prompt = (
        "seamless continuation of the surrounding background, natural texture, "
        "consistent lighting and perspective"
    )
    negative_prompt = (
        "text, letters, words, typography, caption, subtitle, watermark, logo, "
        "signature, label, sign, poster, banner, white rectangle, black characters"
    )

    def run(self, image, *, mask, prompt="", steps=25, progress=None, **_):
        if self._model is None:
            try:
                from diffusers import AutoPipelineForInpainting
                dtype = torch.float16 if torch.cuda.is_available() else torch.float32
                self._model = AutoPipelineForInpainting.from_pretrained(
                    self.model_id, torch_dtype=dtype, cache_dir=str(HF_HOME)
                )
                self._model.enable_attention_slicing()
                self._model.enable_vae_slicing()
                self._model.to("cuda" if torch.cuda.is_available() else "cpu")
            except Exception as exc:
                raise AlgorithmError(f"无法加载 SDXL（首次会下载约 7GB）：{exc}") from exc
        prompt = prompt.strip() or self.default_prompt
        original = image.convert("RGB")
        original_mask = mask.convert("L")
        width, height = original.size
        work_size = (max(8, round(width / 8) * 8), max(8, round(height / 8) * 8))
        work_image = original if original.size == work_size else original.resize(work_size, Image.Resampling.LANCZOS)
        work_mask = original_mask if original_mask.size == work_size else original_mask.resize(work_size, Image.Resampling.NEAREST)
        step_count = max(1, min(int(steps), 50))
        call_options = {
            "prompt": prompt,
            "negative_prompt": self.negative_prompt,
            "image": work_image,
            "mask_image": work_mask,
            "height": work_size[1],
            "width": work_size[0],
            "num_inference_steps": step_count,
        }
        if progress:
            def on_step_end(pipe, step, timestep, callback_kwargs):
                progress(step, step_count)
                return callback_kwargs
            call_options["callback_on_step_end"] = on_step_end
            call_options["callback_on_step_end_tensor_inputs"] = []
        try:
            generated = self._model(**call_options).images[0].convert("RGB")
        except TypeError:
            call_options.pop("callback_on_step_end", None)
            call_options.pop("callback_on_step_end_tensor_inputs", None)
            generated = self._model(**call_options).images[0].convert("RGB")
        if generated.size != original.size:
            generated = generated.resize(original.size, Image.Resampling.LANCZOS)
        return Image.composite(generated, original, original_mask)


class RealESRGAN(Adapter):
    title, task = "Real-ESRGAN", "restore"
    weight_url = "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"

    def run(self, image, *, scale=2, **_):
        if self._model is None:
            try:
                ensure_torchvision_functional_tensor()
                from realesrgan import RealESRGANer
                from basicsr.archs.rrdbnet_arch import RRDBNet
                from torch.hub import load_state_dict_from_url
                path = WEIGHTS_DIR / "RealESRGAN_x4plus.pth"
                if not path.exists():
                    load_state_dict_from_url(self.weight_url, model_dir=str(WEIGHTS_DIR), file_name=path.name)
                net = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=64, num_block=23, num_grow_ch=32, scale=4)
                self._model = RealESRGANer(scale=4, model_path=str(path), model=net, tile=512,
                    tile_pad=10, pre_pad=0, half=torch.cuda.is_available(), device="cuda" if torch.cuda.is_available() else "cpu")
            except Exception as exc:
                raise AlgorithmError(f"无法加载 Real-ESRGAN：{exc}") from exc
        bgr = np.asarray(image.convert("RGB"))[:, :, ::-1]
        output, _ = self._model.enhance(bgr, outscale=float(scale))
        return Image.fromarray(output[:, :, ::-1])


class GFPGAN(Adapter):
    title, task = "GFPGAN（人脸）", "restore"
    weight_url = "https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth"

    def run(self, image, *, scale=2, **_):
        if self._model is None:
            try:
                ensure_torchvision_functional_tensor()
                from gfpgan import GFPGANer
                from torch.hub import load_state_dict_from_url
                path = WEIGHTS_DIR / "GFPGANv1.4.pth"
                if not path.exists():
                    load_state_dict_from_url(self.weight_url, model_dir=str(WEIGHTS_DIR), file_name=path.name)
                self._model = GFPGANer(model_path=str(path), upscale=2, arch="clean", channel_multiplier=2,
                    bg_upsampler=None, device="cuda" if torch.cuda.is_available() else "cpu")
            except Exception as exc:
                raise AlgorithmError(f"无法加载 GFPGAN：{exc}") from exc
        bgr = np.asarray(image.convert("RGB"))[:, :, ::-1]
        _, _, output = self._model.enhance(bgr, has_aligned=False, only_center_face=False, paste_back=True)
        return Image.fromarray(output[:, :, ::-1])


ADAPTERS = {
    "simple-lama": SimpleLama(), "sdxl": SDXLInpaint(),
    "realesrgan": RealESRGAN(), "gfpgan": GFPGAN(),
}

def algorithms():
    return [{"id": key, "title": item.title, "task": item.task} for key, item in ADAPTERS.items()]
