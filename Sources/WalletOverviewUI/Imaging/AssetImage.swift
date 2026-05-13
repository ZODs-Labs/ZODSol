import AppKit
import SwiftUI

/// SwiftUI image view backed by the project's `ImageLoader`. Drives loading
/// through a `.task(id:)` keyed on a request value so the fetch reruns when
/// any input that affects URL selection changes - not just the primary URL.
/// The loader's in-memory cache makes re-renders (e.g. the 15 s overview
/// poll tick) a no-op so already-loaded thumbnails do not flicker.
struct AssetImage<Placeholder: View>: View {
    let url: URL?
    let fallbacks: [URL]
    let pixelWidth: Int
    let placeholder: () -> Placeholder

    @Environment(\.imageLoader) private var loader
    @State private var image: NSImage?

    init(
        url: URL?,
        fallbacks: [URL] = [],
        pixelWidth: Int,
        @ViewBuilder placeholder: @escaping () -> Placeholder)
    {
        self.url = url
        self.fallbacks = fallbacks
        self.pixelWidth = pixelWidth
        self.placeholder = placeholder
    }

    var body: some View {
        let request = AssetImageRequest(
            url: self.url,
            fallbacks: self.fallbacks,
            pixelWidth: self.pixelWidth)
        return Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                self.placeholder()
            }
        }
        .task(id: request) {
            self.image = nil
            await self.load(request)
        }
    }

    private func load(_ request: AssetImageRequest) async {
        guard let url = request.url, let loader else { return }
        let primary = HeliusCDNRewriter.optimized(url, pixelWidth: request.pixelWidth) ?? url
        let chain = AssetImageFallbacks.chain(
            url: url,
            primary: primary,
            initial: request.fallbacks)
        let result = await loader.image(for: primary, fallbacks: chain)
        if !Task.isCancelled {
            self.image = result
        }
    }
}

/// Hashable bundle of every input that affects which URL the loader picks.
/// Used as the `.task(id:)` key so SwiftUI reruns the fetch when fallbacks
/// or the requested pixel width change, not just when the primary URL does.
private struct AssetImageRequest: Hashable {
    let url: URL?
    let fallbacks: [URL]
    let pixelWidth: Int
}

extension EnvironmentValues {
    @Entry public var imageLoader: ImageLoader?
}
