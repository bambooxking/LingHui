#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Inpainting Web ==="
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] uv is not installed or not in PATH."
  echo "Install it with: brew install uv"
  exit 1
fi

echo "Synchronizing dependencies..."
if ! uv sync --no-sources-package torch --no-sources-package torchvision; then
  echo "[ERROR] Dependency synchronization failed."
  exit 1
fi

echo "Starting server at http://0.0.0.0:5500"
(sleep 2 && open http://127.0.0.1:5500) &
exec uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port 5500
