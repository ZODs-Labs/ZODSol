import Formatters
import SolanaKit
import SwiftUI

/// Chromeless NFT tile strip. The section label and total count live on the
/// parent view's header (matching the macOS popover pattern of labelled
/// sections separated by hairlines), so this view renders only the artwork
/// row.
struct NFTSummaryCard: View {
    let summary: NFTSummary

    private let tileSize: CGFloat = 40
    private let maxTiles: Int = 6

    var body: some View {
        if self.summary.isEmpty {
            Text("No NFTs in this wallet")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            HStack(spacing: 6) {
                let previews = Array(summary.collectionPreviews.prefix(self.maxTiles))
                ForEach(Array(previews.enumerated()), id: \.offset) { _, url in
                    self.tile(url: url)
                }
                let remaining = self.summary.count - previews.count
                if remaining > 0 {
                    self.overflowTile(extra: remaining)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tile(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Rectangle().fill(.secondary.opacity(0.12))
            @unknown default:
                Rectangle().fill(.secondary.opacity(0.12))
            }
        }
        .frame(width: self.tileSize, height: self.tileSize)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.secondary.opacity(0.12), lineWidth: 0.5))
    }

    private func overflowTile(extra: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.secondary.opacity(0.12))
            Text("+\(extra)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: self.tileSize, height: self.tileSize)
    }
}
