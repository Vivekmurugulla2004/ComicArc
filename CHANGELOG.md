# Changelog

All notable changes to ComicArc are documented here.

---

## [1.0.0] — 2026-05-08

First public release.

### App
- Native macOS app bundle (.app) — no Python or Terminal required
- Built with PyWebView + PyInstaller; runs fully offline
- Native folder-picker dialog for choosing library location
- All data stored in `~/Library/Application Support/ComicArc/` (database, covers, config)
- Auto-scans library folder on every launch to pick up newly added files

### Onboarding
- First-launch wizard: choose folder → live scan progress → pick default reading mode
- Config persisted to `config.json` (library path, reader mode, onboarding flag)
- Reset Setup in Settings re-runs the wizard without losing any library data

### Library
- Drag-and-drop and folder import for CBZ, CBR, PDF, JPG, JPEG, PNG
- Grid view with cover thumbnails, reading progress bars, and star ratings
- Publisher tabs, tag chips, and free-text search (title / series) filtering
- **Continue Reading** shelf on the library home page
- Favorites and **Want to Read** reading queue
- Metadata editor — edit title, series, publisher, issue number, tags per comic
- Bulk select mode — shift-click range select; mark read/unread, add to reading list, delete
- Manual drag-and-drop reordering (sort: Manual Order)
- Mark Unread button on comic detail page
- Delete with confirmation (removes from library; original file stays on disk)

### Reader
- Page-by-page navigation — keyboard (`←` `→` `Space` `Home` `End`) and touch swipe
- Vertical scroll mode for manga-style reading
- Double-page spread mode
- Zoom up to 5× with click-and-drag panning
- Autoplay — auto-advances every 10 seconds with a visible countdown bar (`A`)
- Auto-hiding toolbar — fades after 3 seconds of inactivity, returns on mouse move
- Press `M` to manually show/hide toolbar at any time
- In-reader keyboard shortcut reference (`?` button or `?` key)
- Default reader mode preference (page / scroll) saved from onboarding and settings
- Progress saves automatically on each page turn and immediately on window close
- Rating modal pre-fills existing rating when reopened
- Ratings from the detail page preserve any review written in the reader

### Narrative Runs
- Create ordered reading lists spanning multiple series and publishers
- Add any library comic to a run
- Drag-and-drop reordering within a run
- Per-issue notes, ratings, and favorites
- Resume button finds the first unfinished issue automatically
- Auto-advances to next comic at end of each issue

### Stats
- Total comics, pages read, favorites, in-progress count, and run count
- Completion tracking (finished / in-progress / unread)
- Publisher breakdown with visual bar chart
- Top series by issue count
- Recently read history

### Settings
- Change library folder and trigger rescan from within the app
- Switch default reader mode (page / scroll)
- CBR support: one-click "Install via Homebrew" with live install log
- Export full library as JSON backup (comics, progress, ratings, tags, runs, reading list)
- Reset Setup — re-run onboarding without losing data
- Clear Library — remove all app data (files stay on disk)

### Technical
- Flask + SQLite backend wrapped in a PyWebView native window
- Background scanner thread with file-signature deduplication (filename + size)
- Scanner never overwrites user-edited metadata on re-scan
- `ON DELETE CASCADE` foreign keys for clean data removal
- Bulk API endpoints for delete, mark-read, mark-unread, reading-list
- Cover thumbnails cached to disk; served with 24-hour cache headers
- PyInstaller bundle excludes personal dev-cache files — clean 70 MB distribution
- No accounts, no cloud, no external network requests
