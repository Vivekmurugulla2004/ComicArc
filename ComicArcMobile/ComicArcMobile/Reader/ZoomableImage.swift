import SwiftUI

/// A zoomable, pannable image view — pinch to zoom, double-tap to fit/fill, drag to pan.
/// `scale` is owned by the parent so it can reset on page navigation and drive double-tap zoom.
struct ZoomableImage: View {
    let image: UIImage
    @Binding var scale: CGFloat

    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale)
                .offset(offset)
                // Pinch-to-zoom — always active
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastScale
                            lastScale = value
                            scale = min(max(scale * delta, minScale), maxScale)
                        }
                        .onEnded { _ in
                            lastScale = 1
                            if scale <= minScale {
                                withAnimation { scale = minScale; offset = .zero }
                            }
                        }
                )
                // Pan — only active when zoomed in; when scale == 1 the mask is .none
                // so this gesture is never recognised and TabView's swipe fires freely.
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width:  lastOffset.width  + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                            clampOffset(in: geo.size)
                        },
                    including: scale > minScale ? .all : .none
                )
                // Reset pan offset when scale is driven back to 1 from outside
                .onChange(of: scale) { _, newScale in
                    if newScale <= minScale {
                        withAnimation { offset = .zero; lastOffset = .zero }
                    }
                }
        }
    }

    private func clampOffset(in size: CGSize) {
        let maxX = (size.width  * (scale - 1)) / 2
        let maxY = (size.height * (scale - 1)) / 2
        withAnimation(.spring(response: 0.3)) {
            offset = CGSize(
                width:  min(maxX, max(-maxX, offset.width)),
                height: min(maxY, max(-maxY, offset.height))
            )
            lastOffset = offset
        }
    }
}
