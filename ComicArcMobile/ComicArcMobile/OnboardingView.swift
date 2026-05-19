import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject var library: LibraryViewModel
    @AppStorage("onboardingDone") private var onboardingDone = false
    @State private var showPicker = false

    var body: some View {
        ZStack {
            Color.arcBg.ignoresSafeArea()
            VStack(spacing: .arcS32) {
                Spacer()
                VStack(spacing: .arcS16) {
                    Text("◈")
                        .font(.system(size: 72))
                        .foregroundStyle(Color.arcGold)
                    Text("ComicArc")
                        .font(.system(size: 42, weight: .heavy))
                        .foregroundStyle(.white)
                    Text("Your personal comic library")
                        .font(.subheadline)
                        .foregroundStyle(Color.arcMuted)
                }
                Spacer()
                VStack(spacing: .arcS16) {
                    featureRow(icon: "books.vertical.fill",  text: "Organize your entire collection")
                    featureRow(icon: "book.fill",            text: "Read CBZ, PDF, and more")
                    featureRow(icon: "chart.bar.fill",       text: "Track reading progress and stats")
                    featureRow(icon: "heart.fill",           text: "Rate, favorite, and tag issues")
                }
                .padding(.horizontal, .arcS32)
                Spacer()
                VStack(spacing: .arcS12) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("Add Comics", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.arcGold)
                            .foregroundStyle(Color.arcBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Button("Start with Empty Library") {
                        onboardingDone = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.arcMuted)
                }
                .padding(.horizontal, .arcS32)
                .padding(.bottom, .arcS32)
            }
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.init(filenameExtension: "cbz")!, .init(filenameExtension: "cbr")!, .pdf, .image],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                library.importFiles(urls)
            }
            onboardingDone = true
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: .arcS12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.arcGold)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
        }
    }
}
