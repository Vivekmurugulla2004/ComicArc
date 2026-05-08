#!/bin/bash
set -e
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
echo "Run: source venv/bin/activate && python app.py"
echo "Open: http://localhost:5001"
