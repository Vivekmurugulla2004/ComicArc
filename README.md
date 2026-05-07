# ComicArc

A local, personal comic book library and reader. Import your own CBZ, CBR, PDF, and image files and read them in your browser — runs entirely on your own machine, no cloud, no accounts, no data ever leaves your device.

> **Important:** ComicArc is a personal reading tool, like Plex for comics. It is intended only for files you legally own or have the legal right to access. See [LEGAL.md](LEGAL.md) before using.

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

## Requirements

- Python 3.9+
- For CBR files: [unar](https://theunarchiver.com/command-line) — `brew install unar` on macOS
- For PDF files: PyMuPDF — `pip install pymupdf`

---

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/Vivekmurugulla2004/Comic-Book-App.git
cd comicarc

# 2. Create a virtual environment
python3 -m venv venv
source venv/bin/activate       # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Run the app
python app.py
```

Open [http://localhost:5001](http://localhost:5001) in your browser.

To quit, press `Ctrl+C` in the terminal.

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
| `.cbr` | Requires `unar` (`brew install unar`) |
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
comicarc/
├── app.py              # Flask routes and API
├── comic_reader.py     # CBZ/CBR/PDF/image page extraction
├── database.py         # SQLite schema and migrations
├── requirements.txt    # Python dependencies
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

- **GitHub:** [github.com/Vivekmurugulla2004/Comic-Book-App](https://github.com/Vivekmurugulla2004/Comic-Book-App)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

This license covers the **software** only. It does not grant any rights to any comic book content, artwork, characters, or stories that may be accessed through this software.
