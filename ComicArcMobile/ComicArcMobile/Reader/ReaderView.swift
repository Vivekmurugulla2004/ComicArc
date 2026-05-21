import SwiftUI
import PDFKit

struct ReaderView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    let comic: Comic
    var runQueue: [Comic] = []

    @State private var activeComic: Comic
    @State private var currentPage: Int = 0
    @State private var readMode: ReadMode = .paged
    @State private var showToolbar = true
    @State private var showRatingSheet = false
    @State private var showThumbnailStrip = false
    @State private var showRunNavigator = false
    @State private var showAddToRunSheet = false
    @State private var zoomScale: CGFloat = 1
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("autoplayInterval") private var storedInterval: Double = 10
    @AppStorage("defaultReadMode")  private var defaultReadMode: String = "paged"
    @FocusState private var readerFocused: Bool

    @State private var autoplayOn = false
    @State private var autoplayCountdown: Double = 10
    @State private var autoplayTimer: Timer?

    @State private var nextComic: Comic?
    @State private var showNextComicBanner = false

    enum ReadMode { case paged, scroll }

    init(comic: Comic, runQueue: [Comic] = []) {
        self.comic    = comic
        self.runQueue = runQueue
        self._activeComic = State(initialValue: comic)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if activeComic.fileExtension == "pdf" {
                    PDFReaderView(url: URL(fileURLWithPath: activeComic.filePath),
                                  currentPage: $currentPage)
                        .simultaneousGesture(TapGesture().onEnded { withAnimation { showToolbar.toggle() } })
                } else if readMode == .scroll {
                    ScrollReaderView(comic: activeComic, currentPage: $currentPage)
                        .onTapGesture { withAnimation { showToolbar.toggle() } }
                } else {
                    PagedReaderView(
                        comic: activeComic,
                        currentPage: $currentPage,
                        zoomScale: $zoomScale,
                        onTapCenter: { withAnimation { showToolbar.toggle() } }
                    )
                }
            }
            .id(activeComic.id)
            .onChange(of: currentPage) { _, page in
                library.updateProgress(activeComic, page: page)
                if autoplayOn { resetAutoplayTimer() }
                checkRunAdvance(page: page)
            }

            if showRunNavigator && !runQueue.isEmpty {
                VStack {
                    runNavigatorStrip
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: showRunNavigator)
            }

            if showToolbar { toolbar }

            if showThumbnailStrip && activeComic.pageCount > 0 {
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
            currentPage = activeComic.progress
            readMode = defaultReadMode == "scroll" ? .scroll : .paged
            updateRunContext(for: activeComic)
            readerFocused = true
        }
        .onDisappear {
            stopAutoplay()
            library.apply(.setProgress(id: activeComic.id, page: currentPage))
        }
        .sheet(isPresented: $showRatingSheet) {
            RatingSheet(comic: activeComic)
                .environmentObject(library)
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddToRunSheet) {
            AddToRunView(comicId: activeComic.id)
        }
    }

    private var isLandscapePhone: Bool { verticalSizeClass == .compact }

    private var toolbar: some View {
        Group {
            if isLandscapePhone {
                HStack {
                    toolbarContent
                    if activeComic.pageCount > 0 {
                        pageSlider.frame(maxWidth: 200)
                    }
                }
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack {
                    toolbarContent
                    Spacer()
                    pageSlider
                }
            }
        }
        .transition(.opacity)
    }

    private var toolbarContent: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close reader")

            if !runQueue.isEmpty {
                Button {
                    withAnimation { showRunNavigator.toggle() }
                } label: {
                    Image(systemName: showRunNavigator ? "list.bullet.circle.fill" : "list.bullet.circle")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(showRunNavigator ? "Hide run navigator" : "Show run navigator")
            }

            Spacer()

            if autoplayOn {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.3), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: storedInterval > 0 ? autoplayCountdown / storedInterval : 0)
                        .stroke(Color.arcGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 28, height: 28)
                .animation(.linear(duration: 1), value: autoplayCountdown)
                .accessibilityLabel("Autoplay countdown, \(Int(autoplayCountdown)) seconds remaining")
            }

            if zoomScale > 1.05 {
                Button {
                    withAnimation(.spring(response: 0.3)) { zoomScale = 1 }
                } label: {
                    Text(String(format: "%.1f×", zoomScale))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.arcGold.opacity(0.25), in: Capsule())
                        .foregroundStyle(Color.arcGold)
                }
                .accessibilityLabel("Reset zoom, currently at \(String(format: "%.1f", zoomScale)) times")
            } else if activeComic.pageCount > 0 {
                Text("\(currentPage + 1) / \(activeComic.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityLabel("Page \(currentPage + 1) of \(activeComic.pageCount)")
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

                if activeComic.pageCount > 0 {
                    Button {
                        withAnimation { showThumbnailStrip.toggle() }
                    } label: {
                        Label(showThumbnailStrip ? "Hide Page Navigator" : "Page Navigator",
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
        if activeComic.pageCount > 0 {
            Slider(value: Binding(
                get: { Double(currentPage) },
                set: { currentPage = Int($0) }
            ), in: 0...Double(max(activeComic.pageCount - 1, 0)), step: 1)
            .tint(.arcGold)
            .padding(.horizontal)
            .padding(.bottom, isLandscapePhone ? 0 : 8)
        }
    }

    private var runNavigatorStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(runQueue) { comic in
                        RunNavCell(
                            comic: comic,
                            isCurrent: comic.id == activeComic.id
                        )
                        .id(comic.id)
                        .onTapGesture {
                            guard comic.id != activeComic.id else { return }
                            switchComic(to: comic)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(.ultraThinMaterial)
            .onAppear { proxy.scrollTo(activeComic.id, anchor: .center) }
            .onChange(of: activeComic.id) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(0..<max(1, activeComic.pageCount), id: \.self) { i in
                        ThumbnailPageCell(comic: activeComic, index: i, isCurrent: i == currentPage)
                            .id(i)
                            .onTapGesture { withAnimation { currentPage = i } }
                            .accessibilityLabel("Page \(i + 1)")
                            .accessibilityAddTraits(i == currentPage ? .isSelected : [])
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

    private func nextComicBanner(_ next: Comic) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                CoverImage(comic: next)
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
                    switchComic(to: next)
                } label: {
                    Text("Read")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.arcGold)
                        .foregroundStyle(Color.arcBg)
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

    private func switchComic(to comic: Comic) {
        library.apply(.setProgress(id: activeComic.id, page: currentPage))
        withAnimation(.easeInOut(duration: 0.2)) {
            activeComic = comic
            currentPage = comic.progress
            zoomScale   = 1
            showNextComicBanner = false
            updateRunContext(for: comic)
        }
    }

    private func updateRunContext(for comic: Comic) {
        guard let idx = runQueue.firstIndex(where: { $0.id == comic.id }) else {
            nextComic = nil; return
        }
        nextComic = idx + 1 < runQueue.count ? runQueue[idx + 1] : nil
    }

    private func checkRunAdvance(page: Int) {
        guard nextComic != nil,
              activeComic.pageCount > 1,
              page >= activeComic.pageCount - 2 else { return }
        withAnimation { showNextComicBanner = true }
    }

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
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                autoplayCountdown -= 1
                if autoplayCountdown <= 0 {
                    advancePage()
                    autoplayCountdown = interval
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        autoplayTimer = timer
    }

    private func advancePage() {
        if currentPage < activeComic.pageCount - 1 {
            currentPage += 1
        } else {
            stopAutoplay()
        }
    }

    private func movePage(_ delta: Int) {
        let target = currentPage + delta
        guard target >= 0, target < activeComic.pageCount else { return }
        currentPage = target
    }
}

struct PagedReaderView: View {
    let comic: Comic
    @Binding var currentPage: Int
    @Binding var zoomScale: CGFloat
    var onTapCenter: () -> Void = {}

    @AppStorage("rtlMode") private var rtlMode = false

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

            .onTapGesture { location in
                guard zoomScale <= 1 else { return }
                let isLeft  = location.x < geo.size.width / 3
                let isRight = location.x > geo.size.width * 2 / 3
                let wantPrev = rtlMode ? isRight : isLeft
                let wantNext = rtlMode ? isLeft  : isRight
                if wantPrev {
                    if currentPage > 0 { currentPage -= 1 }
                } else if wantNext {
                    if currentPage < comic.pageCount - 1 { currentPage += 1 }
                } else {
                    onTapCenter()
                }
            }
            .onTapGesture(count: 2) {
                withAnimation(.spring()) { zoomScale = zoomScale > 1 ? 1 : 2.5 }
            }
        }
        .onChange(of: currentPage) { _, _ in
            withAnimation(.spring(response: 0.3)) { zoomScale = 1 }
        }
    }
}

struct ScrollReaderView: View {
    let comic: Comic
    @Binding var currentPage: Int

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<max(1, comic.pageCount), id: \.self) { index in
                        AsyncPageImage(comic: comic, index: index, zoomable: false)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ScrollPageKey.self,
                                        value: [ScrollPageItem(
                                            index: index,
                                            midY:  geo.frame(in: .named("scrollReader")).midY
                                        )]
                                    )
                                }
                            )
                    }
                }
            }
            .coordinateSpace(name: "scrollReader")
            .onPreferenceChange(ScrollPageKey.self) { pages in
                let viewportMid = viewport.size.height / 2
                if let closest = pages.min(by: {
                    abs($0.midY - viewportMid) < abs($1.midY - viewportMid)
                }) {
                    currentPage = closest.index
                }
            }
        }
    }
}

private struct ScrollPageItem: Equatable {
    let index: Int
    let midY: CGFloat
}

private struct ScrollPageKey: PreferenceKey {
    static var defaultValue: [ScrollPageItem] = []
    static func reduce(value: inout [ScrollPageItem], nextValue: () -> [ScrollPageItem]) {
        value.append(contentsOf: nextValue())
    }
}

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
    @State private var loadFailed = false

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
            } else if loadFailed {
                Color.black
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(Color.arcMuted)
                            Text("Page unavailable")
                                .font(.caption)
                                .foregroundStyle(Color.arcMuted)
                        }
                    }
                    .aspectRatio(2/3, contentMode: .fit)
            } else {
                Color.black
                    .overlay { ProgressView().tint(.white) }
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .task(id: index) {
            loadFailed = false
            image = nil
            await load()
        }
    }

    private func load() async {
        guard let result = await loadPageImage(comic: comic, index: index) else {
            loadFailed = true
            return
        }
        image = result
    }
}

struct PDFReaderView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales       = true
        view.displayMode      = .singlePage
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor  = .black
        view.document         = PDFDocument(url: url)
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
        deinit { NotificationCenter.default.removeObserver(self) }

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

struct RatingSheet: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    let comic: Comic
    @State private var rating: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("Rate this comic").font(.headline)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(i <= rating ? Color.arcGold : Color.secondary)
                        .onTapGesture { rating = i }
                }
            }
            Button("Save") {
                library.apply(.setRating(id: comic.id, value: rating))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.arcGold)
        }
        .padding()
        .onAppear { rating = comic.rating }
    }
}

private struct ThumbnailPageCell: View {
    let comic: Comic
    let index: Int
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFit()
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
                .stroke(isCurrent ? Color.arcGold : Color.white.opacity(0.15),
                        lineWidth: isCurrent ? 2 : 1)
        )
        .scaleEffect(isCurrent ? 1.08 : 1)
        .animation(.easeInOut(duration: 0.15), value: isCurrent)
        .task(id: index) { image = await loadPageImage(comic: comic, index: index) }
    }
}

private struct RunNavCell: View {
    let comic: Comic
    let isCurrent: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.arcCard.overlay {
                        Image(systemName: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 48, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isCurrent ? Color.arcGold : Color.white.opacity(0.2),
                            lineWidth: isCurrent ? 2.5 : 1)
            )
            .overlay(alignment: .bottomTrailing) {
                if comic.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .background(Circle().fill(Color.black).padding(-1))
                        .padding(2)
                }
            }
            .scaleEffect(isCurrent ? 1.08 : 1)
            .animation(.easeInOut(duration: 0.15), value: isCurrent)

            if isCurrent {
                Capsule()
                    .fill(Color.arcGold)
                    .frame(width: 20, height: 3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task(id: comic.id) {
            image = await ThumbnailCache.shared.thumbnail(comic: comic)
        }
        .accessibilityLabel("\(comic.title)\(isCurrent ? ", current" : "")\(comic.isFinished ? ", finished" : "")")
    }
}
