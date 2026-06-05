import SwiftUI
import AppKit

struct CachedArtworkImage<Placeholder: View>: View {
    let url: URL?
    let placeholder: Placeholder

    @State private var image: NSImage?

    init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let url,
              let data = await ArtworkDataCache.shared.data(for: url),
              !Task.isCancelled else {
            return
        }
        image = NSImage(data: data)
    }
}
