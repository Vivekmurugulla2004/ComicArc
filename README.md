# ComicArc

A local comic reader for files you own. No Docker, no accounts, no cloud. Just Python.

> Only import files you legally own or have the right to access. See [LEGAL.md](LEGAL.md).

---

## Quick Start

**macOS (one-click):** Clone the repo, then double-click `ComicArc.command`. It sets up the venv on first run.

**Windows (one-click):** Clone the repo, then double-click `ComicArc.bat`. Same idea — auto-setup on first run.

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

Open [http://localhost:5001](http://localhost:5001) in your browser. Press `Ctrl+C` to quit.

---

## vs. the Alternatives

| | ComicArc | Komga / Kavita | Stump | YACReader | Calibre |
|---|---|---|---|---|---|
| No Docker required | ✓ | ✗ | ✗ | ✓ | ✓ |
| Single-user, no accounts | ✓ | ✗ | ✗ | ✓ | ✓ |
| Narrative Runs | ✓ | ✗ | ✗ | ✗ | ✗ |
| Browser reader + PWA | ✓ | ✓ | ✓ | ✗ | ✗ |
| Setup | `./setup.sh` | Docker + YAML | Docker + YAML | Installer | Installer |

---

## Screenshots

> Coming soon — run locally and take a look.

---

## What This Is

ComicArc is a **single-user, local-first** app that runs on your own computer and serves only you. It has no accounts system, no multi-user support, no server-side storage, and no way to share files with other people. It organizes and serves comic files that live on your hard drive — it does not host, stream, or distribute content.

Think of it the same way you think about:
- **iTunes / Music** — organizes music files you own
- **Plex / Infuse** — organizes video files you own
- **Calibre** — organizes ebook files you own

ComicArc does the same thing for comic files.

---

## Features

**Library**
- Drag-and-drop or folder import for CBZ, CBR, PDF, and image files
- Grid view with cover thumbnails, reading progress, and star ratings
- Filter by publisher, tags, or search by title/series
- Favorites and Continue Reading section
- Metadata editor (title, series, publisher, issue number)

**Reader**
- Page-by-page and vertical scroll (manga) reading modes
- Double-page spread mode
- Zoom and pan
- Autoplay mode — automatically advances pages on a timer
- Keyboard shortcuts (see table below)
- Touch swipe support on mobile
- Progress saves automatically

**Narrative Runs**
- Build ordered reading lists spanning multiple series and publishers
- Drag-and-drop reordering
- Per-issue notes, ratings, and favorites
- Auto-advance between comics in a run

**Stats**
- Total comics, pages read, favorites, completion tracking
- Breakdown by publisher and top series

**Progressive Web App**
- Install to your phone or desktop home screen
- Works offline once loaded (static assets cached)

---

## Why ComicArc Exists

Most tools in this space have a fundamental problem:
- **Marvel Unlimited / DC Universe Infinite / ComiXology** — DRM-locked, subscription-gated, and your access ends when your payment does. ComiXology post-Amazon acquisition gutted offline reading. None support files you bought elsewhere.
- **YACReader** — closest local alternative, but dated UI and no reading-order concept.
- **CDisplayEx** — Windows-only, no web interface, no phone access.
- **Komga / Kavita / Stump** — excellent but designed for multi-user home servers with Docker. Not single-user simplicity. No run/reading-order feature.
- **Calibre** — ebook-first and shows it. No double-page mode, no manga scroll, no progress tracking.

ComicArc is the only local reader with built-in Narrative Runs — cross-series ordered reading lists with per-issue notes and auto-advance. Everything else just organizes files.

---

## Requirements

- Python 3.9+
- For CBR files:
  - **macOS:** `brew install unar`
  - **Linux (Debian/Ubuntu):** `sudo apt install unar`
  - **Linux (Fedora/RHEL):** `sudo dnf install unar`
  - **Windows:** Install [7-Zip](https://www.7-zip.org/) and add it to your PATH — `rarfile` will use it automatically
- For PDF files: PyMuPDF — installed via `pip install -r requirements.txt`

---

## Installation

**macOS (one-click)**

Clone the repo, then double-click `ComicArc.command`. On first run it creates the venv and installs all deps automatically.

**Windows (one-click)**

Clone the repo, then double-click `ComicArc.bat`. On first run it creates the venv and installs all deps automatically.

**macOS / Linux**

```bash
git clone https://github.com/Vivekmurugulla2004/ComicArc.git
cd ComicArc
./setup.sh     # creates venv, installs deps — run once
./run.sh       # starts the server
```

**Windows**

```bat
git clone https://github.com/Vivekmurugulla2004/ComicArc.git
cd ComicArc
setup.bat
run.bat
```

Open [http://localhost:5001](http://localhost:5001) in your browser. Press `Ctrl+C` to quit.

---

## Importing Your Comics

**Browser import (recommended):**

1. Open the app at [http://localhost:5001](http://localhost:5001)
2. Drag and drop files directly onto the import zone, or click **Browse Files** to pick individual files, or click **Import Folder** to import an entire folder at once
3. Supported: `.cbz`, `.cbr`, `.pdf`, `.jpg`, `.jpeg`, `.png`

**Scan from folder (power users):**

Organize your files in `~/Downloads/Comics/` using this folder structure and visit `/scan`:

```
Comics/
  Marvel/
    Spider-Man/
      Amazing Spider-Man #001.cbz
  DC/
    Batman/
      Batman #001.cbr
```

The folder names become the publisher and series in your library automatically.

---

## Supported Formats

| Format | Support |
|--------|---------|
| `.cbz` | Built-in, no extra install needed |
| `.cbr` | Requires `unar` — see Requirements above |
| `.pdf` | Requires PyMuPDF (`pip install pymupdf`) |
| `.jpg` / `.jpeg` / `.png` | Built-in (single-image comics) |

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `←` / `→` | Previous / next page |
| `Space` | Next page |
| `A` | Toggle autoplay (auto-advance every 10 seconds) |
| `V` | Toggle vertical scroll mode |
| `D` | Toggle double-page spread |
| `Z` | Toggle zoom |
| `F` | Toggle fullscreen |
| `Escape` | Exit zoom / close modal / stop autoplay |

---

## Project Structure

```
ComicArc/
├── app.py              # Flask routes and API
├── comic_reader.py     # CBZ/CBR/PDF/image page extraction
├── database.py         # SQLite schema and migrations
├── requirements.txt    # Python dependencies
├── setup.sh            # macOS/Linux setup (run once)
├── run.sh              # macOS/Linux server start
├── setup.bat           # Windows setup (run once)
├── run.bat             # Windows server start
├── ComicArc.command    # macOS double-click launcher
├── ComicArc.bat        # Windows double-click launcher
├── static/
│   ├── css/style.css   # All styles
│   ├── js/reader.js    # Reader logic (navigation, autoplay, zoom)
│   ├── covers/         # Cached cover images (gitignored)
│   ├── icons/          # PWA icons
│   ├── manifest.json   # PWA manifest
│   └── sw.js           # Service worker
├── templates/          # Jinja2 HTML templates
├── user_comics/        # Uploaded comic files (gitignored)
├── comics.db           # SQLite database (gitignored)
├── LEGAL.md            # Content policy and legal notices
├── CONTRIBUTING.md     # Contributor guidelines
├── CHANGELOG.md        # Version history
└── LICENSE             # MIT License
```

---

## Running in Production

By default, ComicArc runs Flask's development server. This is fine for personal local use. If you want to serve it on a home network:

```bash
# Enable production-ish mode (no debug, no auto-reloader)
python app.py  # already defaults to debug=False unless FLASK_DEBUG=true is set
```

**Do not expose ComicArc to the public internet.** It has no authentication and is not designed for multi-user or public access. If you want to access it remotely, use a VPN or SSH tunnel to your home machine.

**Home LAN note:** Serving ComicArc to other devices on your home network (e.g. reading on your phone while the server runs on your desktop) is fine for personal use, but be aware that technically this constitutes multi-user distribution. Keep it to your own devices.

---

## Legal & Content Policy

**Read [LEGAL.md](LEGAL.md) before using or distributing this software.**

The short version:
- Only import files you have the legal right to possess and read
- This tool does not and cannot verify ownership of any file
- You are solely responsible for the content you import
- This software is not intended for, and must not be used for, piracy or unauthorized distribution of copyrighted works

---

## Roadmap

- [ ] ComicVine metadata integration (cover art, descriptions, issue info)
- [ ] Reading statistics and year-in-review
- [ ] Export runs as a shareable reading list (titles only, no files)
- [ ] iOS / Android PWA improvements
- [ ] User accounts and multi-library support (major future version)

---

## Contributing

Pull requests are welcome. For major changes, open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a pull request

Please do not submit pull requests that add functionality for downloading, scraping, or distributing copyrighted comic content from external sources.

---

## Links

- **GitHub:** [github.com/Vivekmurugulla2004/ComicArc](https://github.com/Vivekmurugulla2004/ComicArc)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

This license covers the **software** only. It does not grant any rights to any comic book content, artwork, characters, or stories that may be accessed through this software.
