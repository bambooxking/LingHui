from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models"
HF_HOME = MODELS_DIR / "huggingface"
WEIGHTS_DIR = MODELS_DIR / "weights"
for directory in (HF_HOME, WEIGHTS_DIR):
    directory.mkdir(parents=True, exist_ok=True)
