#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source venv/bin/activate
pip install pyinstaller --quiet
pyinstaller build/ComicArc.spec --clean --noconfirm
echo ""
echo "Done: dist/ComicArc.app"
echo "To create a DMG: hdiutil create -volname ComicArc -srcfolder dist/ComicArc.app -ov -format UDZO dist/ComicArc.dmg"
