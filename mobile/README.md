# ComicArc — iOS

Native SwiftUI app for iPhone and iPad. Reads CBZ and PDF. Tracks progress, ratings, and character/series browsing — same library model as the macOS/Windows desktop app.

## Requirements

- Xcode 15+
- iOS 16+ deployment target
- Swift 5.9+

## Setup

### 1. Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Set:
   - Product Name: `ComicArcMobile`
   - Bundle ID: `com.yourname.ComicArcMobile`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save into this `mobile/` folder

### 2. Add ZIPFoundation (for CBZ reading)

1. **File → Add Package Dependencies**
2. Enter: `https://github.com/weichsel/ZIPFoundation`
3. Version: `0.9.19` or later
4. Add to the `ComicArcMobile` target

### 3. Add the source files

Delete the auto-generated `ContentView.swift` and `<AppName>App.swift` from Xcode, then drag in all the Swift files from `ComicArcMobile/`:

```
ComicArcMobileApp.swift
ContentView.swift
Models/
  Comic.swift
Database/
  DatabaseManager.swift
Library/
  LibraryViewModel.swift
  LibraryView.swift
  ComicCard.swift
  ComicImporter.swift
  ThumbnailCache.swift
Reader/
  CBZReader.swift
  PDFPageCounter.swift
  ReaderView.swift
Settings/
  SettingsView.swift
```

Make sure **"Add to targets: ComicArcMobile"** is checked for each file.

### 4. Info.plist permissions

Add these keys to your `Info.plist`:

| Key | Value |
|-----|-------|
| `UIFileSharingEnabled` | YES |
| `LSSupportsOpeningDocumentsInPlace` | YES |
| `NSDocumentsFolderUsageDescription` | "ComicArc uses your Documents folder to store imported comics." |

### 5. Build and run

Select your simulator or device and hit **Run (⌘R)**.

---

## Features

| Feature | Status |
|---------|--------|
| CBZ reading | Done |
| PDF reading | Done |
| Character/Series/Issue browse (3-level) | Done |
| Reading progress | Done |
| Star ratings | Done |
| Favorites | Done |
| Continue Reading shelf | Done |
| Import from Files app | Done |
| Cover thumbnails (cached to disk) | Done |
| JSON backup export | Done |
| Clear library | Done |
| CBR support | Not yet — no native unrar on iOS |
| Narrative Runs | Not yet |
| iCloud sync | Not yet |
| Stats page | Not yet |

---

## Architecture

| File | Role |
|------|------|
| `DatabaseManager.swift` | SQLite wrapper — same schema as the desktop app |
| `LibraryViewModel.swift` | `@MainActor ObservableObject` — all library state |
| `ComicImporter.swift` | Parses folder structure into metadata, counts pages |
| `ThumbnailCache.swift` | Async cover generation, disk cache |
| `CBZReader.swift` | ZIP extraction via ZIPFoundation |
| `PDFPageCounter.swift` | PDFKit wrapper for page count + rendering |
| `ReaderView.swift` | Paged + vertical scroll reader, PDF native view |

The SQLite schema is compatible with the desktop app. If you have a `comics.db` from the macOS app, you can drop it into the iOS app's Application Support directory and the library will appear immediately.
