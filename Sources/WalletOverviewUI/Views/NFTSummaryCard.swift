import SwiftUI
import SolanaKit
import Formatters

struct NFTSummaryCard: View {
    let summary: NFTSummary

    private let countFormatter = CompactNumberFormatter()
    private let tileSize: CGFloat = 36
    private let maxTiles: Int = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NFTs")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(countFormatter.string(summary.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            content
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var content: some View {
        if summary.isEmpty {
            Text("No NFTs in this wallet")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                let previews = Array(summary.collectionPreviews.prefix(maxTiles))
                ForEach(Array(previews.enumerated()), id: \.offset) { _, url in
                    tile(url: url)
                }
                let remaining = summary.count - previews.count
                if remaining > 0 {
                    overflowTile(extra: remaining)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func tile(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Rectangle().fill(.secondary.opacity(0.15))
            @unknown default:
                Rectangle().fill(.secondary.opacity(0.15))
            }
        }
        .frame(width: tileSize, height: tileSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func overflowTile(extra: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.secondary.opacity(0.15))
            Text("+\(countFormatter.string(extra))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: tileSize, height: tileSize)
    }
}
