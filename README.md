# ComicArc

**A local comic book reader for macOS. No accounts. No cloud. No subscriptions.**

Organize and read your CBZ, CBR, PDF, and image files from a clean, fast native app that lives entirely on your machine.

> Only import files you legally own or have the right to access. See [LEGAL.md](LEGAL.md).

---

## Download

**[→ Download ComicArc v1.0.0](https://github.com/Vivekmurugulla2004/ComicArc/releases/latest)**

Requires macOS 11.0 (Big Sur) or later.

---

## Getting Started

1. Download **ComicArc.app** from the [Releases page](https://github.com/Vivekmurugulla2004/ComicArc/releases)
2. Move it to your **Applications** folder
3. **Right-click the app → Open** (do not double-click the first time — see below)
4. Click **Open** in the dialog that appears
5. A setup wizard walks you through everything

No Python, no terminal, no configuration files required.

---

### First-time macOS warning — read this before you open the app

Because ComicArc is not from the Mac App Store, macOS will block it the first time if you double-click it. Here is the correct way to open it:

1. **Right-click** (or Control-click) the ComicArc icon in your Applications folder
2. Choose **Open** from the menu
3. Click **Open** in the dialog that appears

You only need to do this once. After that, it opens normally like any other app.

If you see "ComicArc is damaged and can't be opened" — open Terminal and run:
```
xattr -cr /Applications/ComicArc.app
```
Then right-click → Open again.

---

---

## First Launch Wizard

The first time you open ComicArc, a short wizard guides you through setup:

1. **Choose your library folder** — select the folder where your comic files live (subfolders are scanned automatically)
2. **Scan** — ComicArc finds and imports everything it recognizes
3. **Pick a reading mode** — page-by-page or continuous scroll

After setup, ComicArc goes straight to your library on every launch and automatically picks up any newly added files.

---

## Features

### Library
- Import by drag-and-drop, file browser, or folder — supports CBZ, CBR, PDF, JPG, PNG
- Grid view with cover thumbnails, reading progress bars, and star ratings
- Filter by publisher tabs, tag chips, or free-text search (title / series)
- **Continue Reading** section on the home page for in-progress comics
- Favorites and **Want to Read** reading queue
- Bulk select — shift-click, select all, mark read/unread, add to list, or delete in one action
- Manual drag-and-drop reordering — drag any card to rearrange; library snaps to Manual Order automatically
- Metadata editor — edit title, series, publisher, issue number, and tags for any comic

### Reader
- **Page-by-page** mode with keyboard and touch navigation
- **Vertical scroll** mode for manga or long-strip comics
- **Double-page spread** mode
- Zoom and pan
- **Autoplay** — auto-advances pages on a 10-second timer with a countdown bar
- Fullscreen mode
- Keyboard shortcut cheat sheet (press `?` anytime in the reader)
- Progress saves automatically on every page turn

### Narrative Runs
- Build ordered reading lists that span multiple series and publishers
- Drag-and-drop to reorder issues within a run
- Per-issue notes, ratings, and favorites
- Auto-advances to the next comic when you finish an issue

### Stats
- Total comics, pages read, favorites, and run count
- Completion breakdown (finished / in-progress / unread)
- Publisher breakdown and top series by issue count
- Recently read history

### Settings
- Change your library folder and rescan at any time
- Switch your default reading mode (page / scroll)
- **CBR support** — one-click Homebrew install of `unar` for CBR/CBR files
- Export your full library as a JSON backup (comics, progress, ratings, tags, runs, reading list)
- Reset the setup wizard without losing any library data
- Clear library — removes all app data while leaving your files on disk

---

## Supported Formats

| Format | Support |
|--------|---------|
| `.cbz` | Built-in |
| `.cbr` | Enable in Settings → CBR Support (one-time internet required to install `unar`) |
| `.pdf` | Built-in |
| `.jpg` / `.jpeg` / `.png` | Built-in |

---

## Keyboard Shortcuts

These shortcuts work anywhere in the reader. Press `?` to see them inside the app.

| Key | Action |
|-----|--------|
| `←` / `→` | Previous / next page |
| `Space` | Next page |
| `Home` | Jump to first page |
| `End` | Jump to last page |
| `V` | Toggle vertical scroll mode |
| `D` | Toggle double-page spread |
| `Z` | Toggle zoom |
| `F` | Toggle fullscreen |
| `A` | Toggle autoplay |
| `?` | Open keyboard shortcut cheat sheet |
| `Escape` | Exit zoom / stop autoplay / close modal |

## Links

This is a personal project. It is not open for contributions — updates will be released here when they're ready.

---

## Legal

Personal use only. Read [LEGAL.md](LEGAL.md) before using.

---

## License

MIT — see [LICENSE](LICENSE). The license covers the software only, not any comic content you import.
