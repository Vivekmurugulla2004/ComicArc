@echo off
cd /d %~dp0..
call venv\Scripts\activate
pip install pyinstaller --quiet
pyinstaller build\ComicArc.spec --clean --noconfirm
echo.
echo Done: dist\ComicArc\ComicArc.exe
