#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source venv/bin/activate
pip install pyinstaller --quiet
pyinstaller build/ComicArc.spec --clean --noconfirm
echo ""
echo "Done: dist/ComicArc/ComicArc"
