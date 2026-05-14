import SwiftUI
import PDFKit

struct ReaderView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var comic: Comic
    /// When reading inside a run, pass all comics so the reader can auto-advance.
    var runQueue: [Comic] = []

    @State private var currentPage: Int = 0
    @State private var readMode: ReadMode = .paged
    @State private var showToolbar = true
    @State private var showRatingSheet = false
    @State private var showThumbnailStrip = false
    @State private var showAddToRunSheet = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("autoplayInterval") private var storedInterval: Double = 10
    @FocusState private var readerFocused: Bool

    // Autoplay
    @State private var autoplayOn = false
    @State private var autoplayCountdown: Double = 10
    @State private var autoplayTimer: Timer?

    // Run auto-advance
    @State private var nextComic: Comic?
    @State private var showNextComicBanner = false

    enum ReadMode { case paged, scroll }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if comic.fileExtension == "pdf" {
                    // simultaneousGesture lets PDFView's UIKit recognizers receive touches
                    // unblocked while still toggling the toolbar on tap.
                    PDFReaderView(url: URL(fileURLWithPath: comic.filePath),
                                  currentPage: $currentPage)
                        .simultaneousGesture(TapGesture().onEnded { withAnimation { showToolbar.toggle() } })
                } else if readMode == .scroll {
                    ScrollReaderView(comic: comic, currentPage: $currentPage)
                        .onTapGesture { withAnimation { showToolbar.toggle() } }
                } else {
                    PagedReaderView(
                        comic: comic,
                        currentPage: $currentPage,
                        onTapCenter: { withAnimation { showToolbar.toggle() } }
                    )
                }
            }
            .onChange(of: currentPage) { _, page in
                library.updateProgress(comic, page: page)
                if autoplayOn { resetAutoplayTimer() }
                checkRunAdvance(page: page)
            }

            if showToolbar { toolbar }

            // Thumbnail strip — independent of toolbar visibility
            if showThumbnailStrip && comic.pageCount > 0 {
                VStack {
                    Spacer()
                    thumbnailStrip
                        .padding(.bottom, showToolbar ? (isLandscapePhone ? 0 : 52) : 0)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: showThumbnailStrip)
            }

            if showNextComicBanner, let next = nextComic {
                nextComicBanner(next)
            }
        }
        .statusBarHidden(!showToolbar)
        .focusable()
        .focused($readerFocused)
        .onKeyPress(.leftArrow)  { movePage(-1); return .handled }
        .onKeyPress(.rightArrow) { movePage(1);  return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "aA")) { _ in movePage(-1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "dD")) { _ in movePage(1);  return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "mM")) { _ in
            withAnimation { showToolbar.toggle() }; return .handled
        }
        .onAppear {
            currentPage = comic.progress
            readMode = UserDefaults.standard.string(forKey: "defaultReadMode") == "scroll" ? .scroll : .paged
            if let idx = runQueue.firstIndex(where: { $0.id == comic.id }),
               idx + 1 < runQueue.count {
                nextComic = runQueue[idx + 1]
            }
            readerFocused = true
        }
        .onDisappear {
            stopAutoplay()
            library.load()
        }
        .sheet(isPresented: $showRatingSheet) {
            RatingSheet(comic: comic)
                .environmentObject(library)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToRunSheet) {
            AddToRunView(comicId: comic.id)
        }
    }

    // MARK: - Toolbar

    private var isLandscapePhone: Bool { verticalSizeClass == .compact }

    private var toolbar: some View {
        Group {
            if isLandscapePhone {
                landscapeToolbar
            } else {
                portraitToolbar
            }
        }
        .transition(.opacity)
    }

    private var portraitToolbar: some View {
        VStack {
            toolbarRow
            Spacer()
            pageSlider
        }
    }

    private var landscapeToolbar: some View {
        HStack {
            toolbarRow
            if comic.pageCount > 0 {
                pageSlider
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var toolbarRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close reader")

            Spacer()

            if autoplayOn {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: storedInterval > 0 ? autoplayCountdown / storedInterval : 0)
                        .stroke(Color.arcGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 28, height: 28)
                .animation(.linear(duration: 1), value: autoplayCountdown)
                .accessibilityLabel("Autoplay countdown, \(Int(autoplayCountdown)) seconds remaining")
            }

            if comic.pageCount > 0 {
                Text("\(currentPage + 1) / \(comic.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Page \(currentPage + 1) of \(comic.pageCount)")
            }

            Spacer()

            Menu {
                Button {
                    withAnimation { readMode = readMode == .paged ? .scroll : .paged }
                } label: {
                    Label(readMode == .paged ? "Switch to Scroll" : "Switch to Paged",
                          systemImage: readMode == .paged ? "scroll" : "book")
                }

                Button {
                    autoplayOn ? stopAutoplay() : startAutoplay()
                } label: {
                    Label(autoplayOn ? "Stop Autoplay" : "Autoplay (\(Int(storedInterval))s)",
                          systemImage: autoplayOn ? "stop.circle" : "play.circle")
                }

                if comic.pageCount > 0 {
                    Button {
                        withAnimation { showThumbnailStrip.toggle() }
                    } label: {
                        Label(showThumbnailStrip ? "Hide Navigator" : "Page Navigator",
                              systemImage: showThumbnailStrip ? "rectangle.compress.vertical" : "square.grid.3x3")
                    }
                }

                Button { showAddToRunSheet = true } label: {
                    Label("Add to Reading Run", systemImage: "list.number")
                }

                Button { showRatingSheet = true } label: {
                    Label("Rate", systemImage: "star")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Reader options")
        }
        .foregroundStyle(.white)
        .padding()
    }

    @ViewBuilder
    private var pageSlider: some View {
        if comic.pageCount > 0 {
            Slider(value: Binding(
                get: { Double(currentPage) },
                set: { currentPage = Int($0) }
            ), in: 0...Double(max(comic.pageCount - 1, 0)), step: 1)
            .tint(.arcGold)
            .padding(.horizontal)
            .padding(.bottom, isLandscapePhone ? 0 : 8)
        }
    }

    // MARK: - Next Comic Banner

    private func nextComicBanner(_ next: Comic) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                CoverImage(comicId: next.id)
                    .frame(width: 44, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Up Next")
                        .font(.caption).foregroundStyle(Color.arcGold)
                    Text(next.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    showNextComicBanner = false
                    dismiss()
                    // The parent run detail will re-present ReaderView with next comic
                    // via the run queue — signal via library state
                    library.pendingRunComic = next
                } label: {
                    Text("Read")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.arcGold)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button { showNextComicBanner = false } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityLabel("Dismiss")
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .padding(.bottom, showToolbar ? 60 : 16)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Run auto-advance

    private func checkRunAdvance(page: Int) {
        guard nextComic != nil,
              comic.pageCount > 0,
              page >= comic.pageCount - 1 else { return }
        withAnimation { showNextComicBanner = true }
    }

    // MARK: - Autoplay

    private func startAutoplay() {
        autoplayOn = true
        autoplayCountdown = storedInterval
        resetAutoplayTimer()
    }

    private func stopAutoplay() {
        autoplayOn = false
        autoplayTimer?.invalidate()
        autoplayTimer = nil
    }

    private func resetAutoplayTimer() {
        autoplayTimer?.invalidate()
        let interval = storedInterval
        autoplayCountdown = interval
        autoplayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                autoplayCountdown -= 1
                if autoplayCountdown <= 0 {
                    advancePage()
                    autoplayCountdown = interval
                }
            }
        }
    }

    private func advancePage() {
        if currentPage < comic.pageCount - 1 {
            currentPage += 1
        } else {
            stopAutoplay()
        }
    }

    private func movePage(_ delta: Int) {
        let target = currentPage + delta
        guard target >= 0, target < comic.pageCount else { return }
        currentPage = target
    }

    // MARK: - Thumbnail Strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(0..<max(1, comic.pageCount), id: \.self) { i in
                        ThumbnailPageCell(comic: comic, index: i, isCurrent: i == currentPage)
                            .id(i)
                            .onTapGesture { withAnimation { currentPage = i } }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 76)
            .background(.ultraThinMaterial)
            .onChange(of: currentPage) { _, page in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(page, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(currentPage, anchor: .center) }
        }
    }
}

// MARK: - Paged Reader

struct PagedReaderView: View {
    let comic: Comic
    @Binding var currentPage: Int
    var onTapCenter: () -> Void = {}

    @State private var zoomScale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $currentPage) {
                ForEach(0..<max(1, comic.pageCount), id: \.self) { index in
                    AsyncPageImage(
                        comic: comic,
                        index: index,
                        zoomScale: index == currentPage ? $zoomScale : .constant(1)
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Double-tap: zoom in/out. Must be on the same view as the single-tap
            // below so SwiftUI coordinates them — count:1 waits for count:2 to fail.
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    zoomScale = zoomScale > 1 ? 1 : 2.5
                }
            }
            // Single-tap with location: left third → prev, right third → next, centre → toolbar
            .onTapGesture { location in
                guard zoomScale <= 1 else { return }
                if location.x < geo.size.width / 3 {
                    if currentPage > 0 { currentPage -= 1 }
                } else if location.x > geo.size.width * 2 / 3 {
                    if currentPage < comic.pageCount - 1 { currentPage += 1 }
                } else {
                    onTapCenter()
                }
            }
        }
        .onChange(of: currentPage) { _, _ in zoomScale = 1 }
    }
}

// MARK: - Scroll Reader

struct ScrollReaderView: View {
    let comic: Comic
    @Binding var currentPage: Int

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<max(1, comic.pageCount), id: \.self) { index in
                    AsyncPageImage(comic: comic, index: index, zoomable: false)
                        .onAppear { currentPage = index }
                }
            }
        }
    }
}

// MARK: - Async Page Image

struct AsyncPageImage: View {
    let comic: Comic
    let index: Int
    let zoomable: Bool
    var zoomScale: Binding<CGFloat>

    init(comic: Comic, index: Int, zoomable: Bool = true,
         zoomScale: Binding<CGFloat> = .constant(1)) {
        self.comic     = comic
        self.index     = index
        self.zoomable  = zoomable
        self.zoomScale = zoomScale
    }

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                if zoomable {
                    ZoomableImage(image: img, scale: zoomScale)
                } else {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                }
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .task(id: index) { await load() }
    }

    private func load() async {
        let cacheKey = PageImageCache.key(filePath: comic.filePath, index: index)
        if let cached = PageImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }
        let filePath = comic.filePath
        let ext      = comic.fileExtension
        let url      = URL(fileURLWithPath: filePath)
        let result: UIImage? = await Task.detached(priority: .userInitiated) {
            switch ext {
            case "cbz":
                return CBZReaderCache.shared.reader(for: filePath)?.image(at: index)
            case "pdf":
                return PDFPageCounter.image(url: url, at: index)
            case "jpg", "jpeg", "png":
                return index == 0 ? UIImage(contentsOfFile: filePath) : nil
            default:
                return nil
            }
        }.value
        if let result {
            let cost = Int(result.size.width * result.scale * result.size.height * result.scale * 4)
            PageImageCache.shared.setImage(result, for: cacheKey, cost: cost)
        }
        image = result
    }
}

// MARK: - PDF Reader (native PDFView)

struct PDFReaderView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales      = true
        view.displayMode     = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = .black
        view.document        = PDFDocument(url: url)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard let doc  = view.document,
              let page = doc.page(at: currentPage),
              view.currentPage != page else { return }
        view.go(to: page)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: PDFReaderView
        init(_ parent: PDFReaderView) { self.parent = parent }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let doc  = view.document else { return }
            DispatchQueue.main.async {
                self.parent.currentPage = doc.index(for: page)
            }
        }
    }
}

// MARK: - Rating Sheet

struct RatingSheet: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    let comic: Comic
    @State private var rating: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Rate this comic")
                .font(.headline)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(i <= rating ? Color.arcGold : Color.secondary)
                        .onTapGesture { rating = i }
                }
            }
            Button("Save") {
                library.setRating(comic, rating: rating)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.arcGold)
        }
        .padding()
        .onAppear { rating = comic.rating }
    }
}

// MARK: - Thumbnail Page Cell

private struct ThumbnailPageCell: View {
    let comic: Comic
    let index: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.black.overlay {
                    ProgressView().scaleEffect(0.5).tint(.white)
                }
            }
        }
        .frame(width: 44, height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isCurrent ? Color.arcGold : Color.white.opacity(0.15), lineWidth: isCurrent ? 2 : 1)
        )
        .scaleEffect(isCurrent ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.15), value: isCurrent)
        .task(id: index) { await load() }
    }

    private func load() async {
        let key = PageImageCache.key(filePath: comic.filePath, index: index)
        if let cached = PageImageCache.shared.image(for: key) { image = cached; return }
        let filePath = comic.filePath
        let ext      = comic.fileExtension
        let url      = URL(fileURLWithPath: filePath)
        let result: UIImage? = await Task.detached(priority: .background) {
            switch ext {
            case "cbz": return CBZReaderCache.shared.reader(for: filePath)?.image(at: index)
            case "pdf": return PDFPageCounter.image(url: url, at: index)
            case "jpg", "jpeg", "png": return index == 0 ? UIImage(contentsOfFile: filePath) : nil
            default:    return nil
            }
        }.value
        if let result {
            let cost = Int(result.size.width * result.scale * result.size.height * result.scale * 4)
            PageImageCache.shared.setImage(result, for: key, cost: cost)
        }
        image = result
    }
}
