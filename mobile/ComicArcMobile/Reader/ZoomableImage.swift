import SwiftUI

/// A zoomable, pannable image view — pinch to zoom, double-tap to fit/fill, drag to pan.
struct ZoomableImage: View {
    let image: UIImage

    @State private var scale: CGFloat = 1
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
                .gesture(
                    SimultaneousGesture(
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
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                                clampOffset(in: geo.size)
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > minScale {
                            scale = minScale
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            scale = 2.5
                        }
                    }
                }
        }
    }

    private func clampOffset(in size: CGSize) {
        let maxX = (size.width * (scale - 1)) / 2
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
