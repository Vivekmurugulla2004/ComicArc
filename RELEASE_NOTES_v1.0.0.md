# ComicArc v1.0.0

First public release of ComicArc — a local comic library and reader built around how people actually read comics: in runs.

---

## What It Does

ComicArc runs entirely on your computer and serves only you. Import your comic files, organize them, and read them in your browser. No accounts. No cloud. No subscriptions. No one can revoke your library.

**Library** — Drag-and-drop import for CBZ, CBR, PDF, and image files. Grid view with covers, reading progress, star ratings, favorites, tags, and search.

**Reader** — Page-by-page navigation, vertical scroll (manga mode), double-page spread, zoom/pan, autoplay with countdown timer, fullscreen, keyboard shortcuts, touch swipe. Progress saves automatically.

**Narrative Runs** — Build ordered reading lists that span series and publishers. Drag-and-drop reordering. Per-issue notes and ratings. Auto-advance between issues.

**Stats** — Pages read, completion tracking, breakdown by publisher and series.

**PWA** — Installable to your phone or desktop home screen. Works offline once loaded.

---

## Requirements

- Python 3.9 or later
- For CBR files: `unar` — `brew install unar` (macOS), `sudo apt install unar` (Linux), 7-Zip in PATH (Windows)
- For PDF files: PyMuPDF — installed via `pip install -r requirements.txt`

---

## Installation

**macOS (one-click):** Clone the repo and double-click `ComicArc.command`.

**Windows (one-click):** Clone the repo and double-click `ComicArc.bat`.

**macOS / Linux:**
```bash
git clone https://github.com/Vivekmurugulla2004/ComicArc.git
cd ComicArc
./setup.sh
./run.sh
```

**Windows:**
```bat
git clone https://github.com/Vivekmurugulla2004/ComicArc.git
cd ComicArc
setup.bat
run.bat
```

Open [http://localhost:5001](http://localhost:5001) in your browser.

---

## Legal

ComicArc is a personal reading tool — the same model as iTunes, Plex, or Calibre, but for comics. It is intended only for files you have the legal right to possess and read. It has no ability to download, share, or distribute content. Read [LEGAL.md](LEGAL.md) before using.

---

## What's New

This is the first public release — see [CHANGELOG.md](CHANGELOG.md) for the full feature list.
