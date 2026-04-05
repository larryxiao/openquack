#!/bin/bash
set -e

echo "=== OpenQuack Setup ==="
echo ""

if [ ! -d ".venv" ]; then
    echo "[1/2] Creating virtual environment..."
    python3 -m venv .venv
else
    echo "[1/2] Virtual environment exists"
fi

source .venv/bin/activate

echo "[2/2] Installing Python dependencies..."
pip install -q -r requirements.txt

echo ""
echo "=== Setup complete ==="
echo ""
echo "Run:"
echo "  source .venv/bin/activate"
echo "  python -m openquack                    # whisper-only (default)"
echo "  python -m openquack --polish           # with LLM cleanup (needs Ollama)"
echo ""
echo "Or via npx:"
echo "  npx .                                  # auto-bootstraps on first run"
echo ""
echo "NOTE: Grant Accessibility permissions to your terminal app"
echo "      System Settings > Privacy & Security > Accessibility"
