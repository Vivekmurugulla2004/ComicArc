# Changelog

All notable changes to ComicArc are documented here.

---

## [1.0.0] — 2026-05-07

First public release.

### Library
- Drag-and-drop and folder import for CBZ, CBR, PDF, JPG, JPEG, and PNG files
- Grid view with cover thumbnails, reading progress bars, and star ratings
- Filter by publisher tabs, tag chips, and free-text search (title/series)
- Favorites and Continue Reading section on the library home page
- Metadata editor — edit title, series, publisher, issue number, tags
- Delete comic with confirmation (removes file and all reading data)

### Reader
- Page-by-page navigation with keyboard (← →, Space) and touch swipe
- Vertical scroll mode for manga-style reading
- Double-page spread mode
- Zoom and pan
- Autoplay mode — auto-advances pages every 10 seconds with countdown bar (toggle with A key)
- Fullscreen mode (F key)
- Progress saves automatically on each page turn
- Auto-advance to next comic when a run is active

### Narrative Runs
- Create ordered reading lists spanning multiple series and publishers
- Add any comic from the library to any run
- Drag-and-drop reordering within a run
- Per-issue notes, star ratings, and favorites
- Auto-advance between comics at end of each issue

### Stats
- Total comics, pages read, and favorites count
- Completion tracking (finished vs. in-progress vs. unread)
- Breakdown by publisher
- Top series by issue count

### Progressive Web App
- Install to phone or desktop home screen via browser prompt
- Static assets cached for offline access
- Service worker with cache-first strategy for static files

### Setup
- `setup.sh` / `setup.bat` — one-command venv creation and dep install
- `run.sh` / `run.bat` — one-command server start
- `ComicArc.command` — macOS double-click launcher (auto-setup on first run)
- `ComicArc.bat` — Windows double-click launcher (auto-setup on first run)

### Technical
- Flask + SQLite backend, runs on Python 3.9+
- Supports CBZ (built-in), CBR (requires unar), PDF (requires PyMuPDF), and single images
- PWA manifest and service worker
- No accounts, no cloud, no external network requests
- All data stays on the user's machine
