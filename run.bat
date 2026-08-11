@echo off
setlocal
cd /d "%~dp0"

echo === Inpainting Web ===
where uv >nul 2>nul
if errorlevel 1 (
  echo [ERROR] uv is not installed or not in PATH.
  echo Install it with: winget install --id=astral-sh.uv -e
  pause
  exit /b 1
)

echo Synchronizing dependencies...
uv sync
if errorlevel 1 (
  echo [ERROR] Dependency synchronization failed.
  pause
  exit /b 1
)

echo Starting server at http://0.0.0.0:5500
start "Open Inpainting Web" cmd /c "timeout /t 2 /nobreak >nul & explorer http://127.0.0.1:5500"
uv run uvicorn app.main:app --host 0.0.0.0 --port 5500

endlocal

