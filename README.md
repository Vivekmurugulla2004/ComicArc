# ComicArc

A local-first comic book library and reading organizer. Import your own CBZ, CBR, and PDF files and read them in the browser — no accounts, no cloud, no subscriptions.

---

## Features

**Library**
- Drag-and-drop or folder import for CBZ, CBR, and PDF files
- Grid view with cover thumbnails, reading progress, and star ratings
- Filter by publisher, tags, or search by title/series
- Favorites and Continue Reading section
- Metadata editor (title, series, publisher, issue number)

**Reader**
- Page-by-page and vertical scroll (manga) reading modes
- Double-page spread mode
- Zoom and pan with scroll wheel or keyboard
- Keyboard shortcuts: `←` `→` to turn pages, `F` fullscreen, `V` vertical mode, `D` spread, `Z` zoom
- Touch swipe support on mobile
- Progress saves automatically

**Narrative Runs**
- Build ordered reading lists spanning multiple series and publishers
- Drag-and-drop reordering
- Per-issue notes, ratings, and favorites
- "Continue reading" jump directly into a run

**Stats**
- Total comics, pages read, favorites, completion tracking
- Breakdown by publisher and top series

**Progressive Web App**
- Install to your phone or desktop home screen
- Works offline once loaded (static assets cached)

---

## Screenshots

> Add screenshots here after setup. Recommended: library grid, reader, run detail page.

---

## Requirements

- Python 3.9+
- For CBR files: [unar](https://theunarchiver.com/command-line) (`brew install unar` on macOS)
- For PDF files: PyMuPDF (`pip install pymupdf`)

---

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/your-username/comicarc.git
cd comicarc

# 2. Create a virtual environment
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 4. Run the app
python app.py
```

Then open [http://localhost:5001](http://localhost:5001) in your browser.

---

## Importing Comics

**From the Library page:**
- Drag and drop CBZ/CBR/PDF files directly onto the import zone
- Click **Browse Files** to select individual files
- Click **Import Folder** to import an entire folder at once

**From your existing collection (macOS):**
Organize your comics in `~/Downloads/Comics/` using the folder structure:
```
Comics/
  Marvel/
    Spider-Man/
      Amazing Spider-Man #001.cbz
  DC/
    Batman/
      Batman #001.cbr
```
Then click **Scan Library** in the nav bar.

---

## Supported Formats

| Format | Support |
|--------|---------|
| `.cbz` | Full (built-in) |
| `.cbr` | Requires `unar` (`brew install unar`) |
| `.pdf` | Requires PyMuPDF (`pip install pymupdf`) |

---

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `←` / `→` | Previous / next page |
| `Space` | Next page |
| `V` | Toggle vertical scroll mode |
| `D` | Toggle double-page spread |
| `Z` | Toggle zoom |
| `F` | Toggle fullscreen |
| `Escape` | Exit zoom / close modal |

---

## Project Structure

```
comicarc/
├── app.py              # Flask routes
├── comic_reader.py     # CBZ/CBR/PDF page extraction
├── database.py         # SQLite schema and migrations
├── static/
│   ├── css/style.css   # All styles
│   ├── js/reader.js    # Reader logic
│   ├── covers/         # Cached cover images (gitignored)
│   ├── icons/          # PWA icons
│   ├── manifest.json   # PWA manifest
│   └── sw.js           # Service worker
├── templates/          # Jinja2 HTML templates
├── user_comics/        # Uploaded comic files (gitignored)
└── comics.db           # SQLite database (gitignored)
```

---

## Roadmap

- [ ] User accounts and cloud sync
- [ ] Public run sharing
- [ ] ComicVine metadata scraping
- [ ] Reading statistics and year-in-review
- [ ] Export runs as PDF or reading list
- [ ] Browser extension for adding comics from the web
- [ ] iOS / Android native app (PWA wrapper)

---

## License

MIT License — see [LICENSE](LICENSE) for details.

---

## Contributing

Pull requests are welcome. For major changes, open an issue first to discuss what you'd like to change.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a pull request
