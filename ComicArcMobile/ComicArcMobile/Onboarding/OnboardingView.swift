import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject var library: LibraryViewModel
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var page = 0
    @State private var showImporter = false
    @State private var showFolderImporter = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.arcBg.ignoresSafeArea()

            TabView(selection: $page) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                importPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: page)

            VStack(spacing: 20) {
                pageDots
                navButtons
            }
            .padding(.bottom, 48)
            .padding(.horizontal, 32)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [
                UTType("com.comicarcapp.cbz") ?? .zip,
                UTType("com.comicarcapp.cbr") ?? .data,
                .pdf, .jpeg, .png
            ],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { library.importFiles(urls) }
            finish()
        }
        .fileImporter(
            isPresented: $showFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                library.importFolder(url)
            }
            finish()
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "book.closed.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.arcGold)
                .shadow(color: Color.arcGold.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text("ComicArc")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Color.arcGold)
                Text("Your comic library,\nalways with you.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Everything you need")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                featureRow(icon: "books.vertical.fill", color: Color.arcGold,
                           title: "Smart Library",
                           body: "Browse by character, series, and publisher. Search, filter, tag, and build collections.")

                featureRow(icon: "book.fill", color: .blue,
                           title: "Immersive Reader",
                           body: "Page, scroll, and zoom. Autoplay, run navigator, progress tracking, and ratings.")

                featureRow(icon: "list.number", color: .purple,
                           title: "Reading Runs",
                           body: "Build story arcs across series. Drag to reorder, track progress issue by issue.")
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var importPage: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.arcGold)
                .padding(.bottom, 20)

            VStack(spacing: 6) {
                Text("Add Your Comics")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Import individual files or an entire folder at once.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 28)

            VStack(spacing: 12) {
                Button {
                    showFolderImporter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Folder")
                                .font(.headline)
                            Text("Bring in your entire collection at once")
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Color.arcGold)
                    .foregroundStyle(Color.arcBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityLabel("Import folder of comics")

                Button {
                    showImporter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Files")
                                .font(.headline)
                            Text("CBZ, CBR, PDF, JPG, PNG")
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .background(Color.arcSurface)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.arcBorder, lineWidth: 1))
                }
                .accessibilityLabel("Import individual comic files")
            }
            .padding(.bottom, 20)

            Button("Skip for now") { finish() }
                .font(.subheadline)
                .foregroundStyle(Color.arcMuted)
                .accessibilityLabel("Skip import for now")

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func featureRow(icon: String, color: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.arcCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.arcBorder, lineWidth: 1))
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i == page ? Color.arcGold : Color.arcBorder)
                    .frame(width: i == page ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: page)
            }
        }
    }

    private var navButtons: some View {
        HStack {
            if page > 0 {
                Button {
                    withAnimation { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Color.arcSurface)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.arcBorder, lineWidth: 1))
                }
                .foregroundStyle(.white)
                .accessibilityLabel("Back")
            } else {
                Spacer().frame(width: 48)
            }

            Spacer()

            if page < 2 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text("Next")
                        .font(.headline)
                        .padding(.horizontal, 32).padding(.vertical, 14)
                        .background(Color.arcGold)
                        .foregroundStyle(Color.arcBg)
                        .clipShape(Capsule())
                }
                .accessibilityLabel("Next")
            }
        }
    }

    private func finish() {
        onboardingDone = true
    }
}
