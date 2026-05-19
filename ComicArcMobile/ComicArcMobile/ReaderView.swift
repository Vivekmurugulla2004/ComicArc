import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    let comic: Comic
    let url: URL

    @AppStorage("defaultReadMode")  private var defaultReadMode  = "page"
    @AppStorage("rtlMode")          private var rtlMode          = false
    @AppStorage("autoplayInterval") private var autoplayInterval = 10.0

    @State private var currentPage: Int
    @State private var totalPages: Int
    @State private var isVertical: Bool
    @State private var isSpread   = false
    @State private var isManga    = false
    @State private var fitMode    = FitMode.contain
    @State private var showChrome = true
    @State private var showNextIssue = false
    @State private var isAutoplay = false
    @State private var autoplayTask: Task<Void, Never>?

    enum FitMode: String, CaseIterable {
        case contain, width, height
        var icon: String {
            switch self { case .contain: "↔"; case .width: "⇔"; case .height: "⇕" }
        }
    }

    init(comic: Comic, url: URL) {
        self.comic = comic
        self.url   = url
        let start = max(0, comic.currentPage)
        _currentPage  = State(initialValue: start)
        _totalPages   = State(initialValue: max(1, comic.pageCount))
        _isVertical   = State(initialValue: false)
        _isManga      = State(initialValue: false)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isVertical {
                verticalReader
            } else {
                pagedReader
            }
            if showChrome { chrome }
            if showNextIssue { nextIssueOverlay }
        }
        .statusBar(hidden: !showChrome)
        .onAppear {
            totalPages = max(1, ComicReader.pageCount(url: url))
            isManga    = rtlMode
            isVertical = defaultReadMode == "scroll"
        }
        .onDisappear {
            autoplayTask?.cancel()
            library.saveProgress(id: comic.id, page: currentPage)
        }
    }

    // MARK: - Paged Reader

    private var pagedReader: some View {
        TabView(selection: $currentPage) {
            ForEach(0..<totalPages, id: \.self) { page in
                PageView(url: url, page: page, fitMode: fitMode)
                    .tag(page)
                    .onTapGesture { showChrome.toggle() }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, isManga ? .rightToLeft : .leftToRight)
        .onChange(of: currentPage) { _, p in
            library.saveProgress(id: comic.id, page: p)
            if p == totalPages - 1 { checkNextIssue() }
        }
    }

    // MARK: - Vertical Reader

    private var verticalReader: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        PageView(url: url, page: page, fitMode: .width)
                            .id(page)
                            .onAppear {
                                currentPage = page
                                library.saveProgress(id: comic.id, page: page)
                            }
                    }
                }
            }
            .onAppear { proxy.scrollTo(currentPage, anchor: .top) }
        }
        .onTapGesture { showChrome.toggle() }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                Text(comic.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, .arcS8)
                Spacer()
                Text("\(currentPage + 1)/\(totalPages)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, .arcS16)
            .padding(.top, 52)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            // Bottom bar
            VStack(spacing: .arcS8) {
                HStack(spacing: .arcS12) {
                    toolbarBtn(icon: isVertical ? "rectangle.portrait.and.arrow.forward" : "arrow.down.to.line", active: isVertical) { isVertical.toggle() }
                    toolbarBtn(icon: "rectangle.landscape.rotate", active: isSpread) {
                        isSpread.toggle()
                    }
                    toolbarBtn(icon: "arrow.right.to.line.compact", active: isManga) {
                        isManga.toggle()
                        rtlMode = isManga
                    }
                    toolbarBtn(icon: fitMode == .contain ? "arrow.up.left.and.arrow.down.right" :
                               fitMode == .width ? "arrow.left.and.right" : "arrow.up.and.down", active: fitMode != .contain) {
                        switch fitMode {
                        case .contain: fitMode = .width
                        case .width:   fitMode = .height
                        case .height:  fitMode = .contain
                        }
                    }
                    toolbarBtn(icon: isAutoplay ? "pause.fill" : "play.fill", active: isAutoplay) {
                        toggleAutoplay()
                    }
                }
                if totalPages > 1 {
                    Slider(value: Binding(
                        get: { Double(currentPage) },
                        set: { currentPage = Int($0) }
                    ), in: 0...Double(totalPages - 1), step: 1)
                    .tint(Color.arcGold)
                    .padding(.horizontal, .arcS8)
                }
            }
            .padding(.arcS16)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
    }

    // MARK: - Next Issue Overlay

    private var nextIssueOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: .arcS20) {
                Text("SERIES COMPLETE")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(Color.arcGold)
                if let next = library.nextInSeries(after: comic) {
                    VStack(spacing: .arcS12) {
                        Text("Up next in \(comic.series)")
                            .font(.subheadline)
                            .foregroundStyle(Color.arcMuted)
                        CoverImage(comic: next)
                            .frame(width: 120, height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: .arcCardRadius))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                        Text(next.title)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        if let url = library.resolvedURL(for: next) {
                            Button {
                                showNextIssue = false
                                dismiss()
                                // Navigation to next issue is handled by presenting a new ReaderView
                            } label: {
                                Label("Continue Reading", systemImage: "arrow.right.circle.fill")
                                    .font(.headline)
                                    .frame(width: 240)
                                    .padding(.vertical, 12)
                                    .background(Color.arcGold)
                                    .foregroundStyle(Color.arcBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                Button("Stay Here") { showNextIssue = false }
                    .font(.subheadline)
                    .foregroundStyle(Color.arcMuted)
            }
            .padding(.arcS32)
        }
    }

    // MARK: - Helpers

    private func checkNextIssue() {
        if library.nextInSeries(after: comic) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showNextIssue = true
            }
        }
    }

    private func toggleAutoplay() {
        isAutoplay.toggle()
        if isAutoplay {
            autoplayTask = Task {
                while !Task.isCancelled && isAutoplay {
                    try? await Task.sleep(nanoseconds: UInt64(autoplayInterval * 1_000_000_000))
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        if currentPage < totalPages - 1 { currentPage += 1 }
                        else { isAutoplay = false }
                    }
                }
            }
        } else {
            autoplayTask?.cancel()
        }
    }

    private func toolbarBtn(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(active ? Color.arcGold : .white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Color.arcGold : Color.clear, lineWidth: 1))
        }
    }
}

// MARK: - Single Page View

struct PageView: View {
    let url: URL
    let page: Int
    let fitMode: ReaderView.FitMode

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: fitMode == .height ? .fit : (fitMode == .width ? .fill : .fit))
                        .frame(
                            width:  fitMode == .width ? geo.size.width : nil,
                            height: fitMode == .height ? geo.size.height : nil
                        )
                        .scaleEffect(scale)
                        .gesture(MagnificationGesture()
                            .onChanged { scale = max(1, $0) }
                            .onEnded   { _ in withAnimation { scale = 1 } }
                        )
                } else {
                    ProgressView().tint(Color.arcGold)
                }
            }
        }
        .task(id: page) { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        image = await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return ComicReader.page(url: url, index: page)
        }.value
    }
}
