@echo off
python -m venv venv
call venv\Scripts\activate
pip install -r requirements.txt
echo Run: run.bat
echo Open: http://localhost:5001
