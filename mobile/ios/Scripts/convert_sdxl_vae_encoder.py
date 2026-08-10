# /// script
# requires-python = ">=3.10,<3.13"
# dependencies = [
#   "coremltools==9.0",
#   "diffusers==0.35.2",
#   "huggingface-hub==0.35.3",
#   "numpy==1.26.4",
#   "safetensors==0.6.2",
#   "torch==2.7.0",
#   "transformers==4.57.1",
# ]
# ///

"""Convert the SDXL FP16-fixed VAE encoder for LingHui's 768px iOS pipeline."""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
from diffusers import AutoencoderKL


MODEL_ID = "madebyollin/sdxl-vae-fp16-fix"
IMAGE_SIZE = 768


class VAEEncoder(torch.nn.Module):
    def __init__(self, vae: AutoencoderKL) -> None:
        super().__init__()
        self.encoder = vae.encoder.to(dtype=torch.float32)
        self.quant_conv = vae.quant_conv.to(dtype=torch.float32)

    def forward(self, z: torch.Tensor) -> torch.Tensor:
        return self.quant_conv(self.encoder(z))


def convert(output: Path) -> None:
    torch.set_grad_enabled(False)
    vae = AutoencoderKL.from_pretrained(
        MODEL_ID,
        torch_dtype=torch.float32,
        use_safetensors=True,
    )
    encoder = VAEEncoder(vae).eval()
    sample = torch.rand(1, 3, IMAGE_SIZE, IMAGE_SIZE, dtype=torch.float32)
    traced = torch.jit.trace(encoder, sample)

    model = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        inputs=[
            ct.TensorType(
                name="z",
                shape=sample.shape,
                dtype=np.float16,
            )
        ],
        outputs=[ct.TensorType(name="latent", dtype=np.float32)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        skip_model_load=True,
    )
    model.author = f"Please refer to the Model Card available at huggingface.co/{MODEL_ID}"
    model.license = "OpenRAIL++-M"
    model.version = MODEL_ID
    model.short_description = (
        "SDXL VAE encoder for 768×768 image-to-image inference in LingHui."
    )
    model.input_description["z"] = (
        "RGB image normalized to [-1, 1], shape 1×3×768×768."
    )
    model.output_description["latent"] = (
        "Diagonal Gaussian moments, shape 1×8×96×96."
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    model.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    convert(args.output.resolve())


if __name__ == "__main__":
    main()
