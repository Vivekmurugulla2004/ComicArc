# ComicArc

**A local comic book reader for macOS. No accounts. No cloud. No subscriptions.**

Organize and read your CBZ, CBR, PDF, and image files in a clean, fast native app that lives entirely on your machine.

> **Only import files you legally own or have the right to access.** See [LEGAL.md](LEGAL.md) for full details.

---

## Download

**[→ Download ComicArc v1.0.0](https://github.com/Vivekmurugulla2004/ComicArc/releases/latest)**

macOS 11.0 (Big Sur) or later — Apple Silicon and Intel supported.

---

## Quick Start

1. Download **ComicArc.zip** from the [Releases page](https://github.com/Vivekmurugulla2004/ComicArc/releases) and unzip it
2. Move **ComicArc.app** to your **Applications** folder
3. **Right-click → Open** (required the first time — see below)
4. Follow the setup wizard: pick your comics folder, scan, choose a reading mode
5. Done — your library is ready

No Python, no Terminal, no configuration files.

---

## Opening for the First Time (macOS Gatekeeper)

Because ComicArc is not from the App Store, macOS will warn you on first launch. This is normal for any independently distributed Mac app.

**The correct way to open it:**

1. Right-click (or Control-click) **ComicArc.app** in Applications
2. Choose **Open** from the menu
3. Click **Open** in the dialog

You only need to do this once. After that it opens normally.

**If you see "ComicArc is damaged and can't be opened"**, run this in Terminal:

```sh
xattr -cr /Applications/ComicArc.app
```

Then right-click → Open again. This removes a macOS quarantine flag that sometimes sticks when downloading through certain browsers.

---

## Features

### Library
- Drag-and-drop or folder import — CBZ, CBR, PDF, JPG, PNG
- Grid view with cover thumbnails, progress bars, and star ratings
- **Continue Reading** shelf on the home page
- Filter by publisher tabs, tag chips, or free-text search
- Favorites and **Want to Read** reading queue
- Bulk select — shift-click, select all, mark read/unread, add to list, delete
- Drag-to-reorder cards with automatic Manual Order mode
- Metadata editor — title, series, publisher, issue number, tags

### Reader
- **Page-by-page** mode — click/tap or keyboard to advance
- **Vertical scroll** mode — continuous strip for manga
- **Double-page spread** mode
- Zoom (up to 5×) with click-and-drag panning
- **Autoplay** — advances every 10 seconds with a visible countdown bar
- Auto-hiding toolbar — fades after 3 seconds, returns on mouse move; press `M` to toggle manually
- In-reader keyboard shortcut reference (press `?`)
- Progress saves automatically on every page turn and on close

### Narrative Runs
- Build ordered reading paths that span multiple series and publishers — like a playlist for comics
- Drag-and-drop to reorder issues within a run
- Per-issue notes, ratings, and favorites inline
- Resume button picks up exactly where you left off
- Auto-advances to the next comic when you finish an issue

### Stats
- Total comics, pages read, favorites, in-progress count, run count
- Publisher breakdown with visual bar chart
- Top series by issue count
- Recently read history

### Settings
- Change library folder and rescan at any time
- Switch default reading mode (page-by-page or scroll)
- **CBR support** — one-click Homebrew install of `unar` right from the Settings page
- Export full library as a JSON backup — comics, progress, ratings, tags, runs, reading list
- Reset Setup wizard without losing library data
- Clear Library — wipes app data, leaves your files untouched

---

## Supported Formats

| Format | Support |
|--------|---------|
| `.cbz` | Built-in |
| `.cbr` | One-time setup in Settings → CBR Support (requires internet to install `unar` via Homebrew) |
| `.pdf` | Built-in |
| `.jpg` / `.jpeg` / `.png` | Built-in |

CBZ, PDF, and images work immediately with no setup. CBR requires a one-time install of `unar` — you can do it from inside the app.

---

## Keyboard Shortcuts

Press `?` in the reader to see these at any time.

| Key | Action |
|-----|--------|
| `←` `→` | Previous / next page |
| `Space` | Next page |
| `Home` | Jump to first page |
| `End` | Jump to last page |
| `V` | Toggle vertical scroll mode |
| `D` | Toggle double-page spread |
| `Z` | Toggle zoom |
| `A` | Toggle autoplay |
| `M` | Show / hide toolbar |
| `?` | Open keyboard shortcut reference |
| `Esc` | Exit zoom / stop autoplay / close modal |

**Touch:** swipe left or right to navigate, or tap the left/right edge of the screen.

---

## Where Your Data Lives

Everything is local. Nothing ever leaves your machine.

| What | Location |
|------|----------|
| Library database | `~/Library/Application Support/ComicArc/comics.db` |
| Cover thumbnails | `~/Library/Application Support/ComicArc/covers/` |
| Settings | `~/Library/Application Support/ComicArc/config.json` |

Your original comic files are **never moved, renamed, or modified.** ComicArc reads them in place.

---

## Works Offline

ComicArc is fully offline after the initial setup. The only action requiring internet is a one-time install of `unar` for CBR support, which you can skip entirely if you don't have CBR files.

---

## What ComicArc Is (and Isn't)

ComicArc is a **single-user, local-first** tool that organizes comic files you already have — the same way Calibre organizes ebooks or Infuse organizes video. It does not download, stream, or distribute content.

This is a personal project. It is not open for contributions. Updates will be released here when ready.

---

## Acknowledgements

ComicArc is built on top of several excellent open-source projects:

- [PyWebView](https://pywebview.flowrl.com/) — native window wrapping the web frontend
- [Flask](https://flask.palletsprojects.com/) — local HTTP server
- [PyMuPDF](https://pymupdf.readthedocs.io/) — PDF rendering
- [Waitress](https://docs.pylonsproject.org/projects/waitress/) — WSGI server
- [PyInstaller](https://pyinstaller.org/) — macOS app bundling
- [Inter](https://rsms.me/inter/) and [Bebas Neue](https://fonts.google.com/specimen/Bebas+Neue) — bundled fonts

---

## Legal

Personal use only. Read [LEGAL.md](LEGAL.md) before using.

## License

MIT — see [LICENSE](LICENSE). The license covers the software only, not any content you import.
