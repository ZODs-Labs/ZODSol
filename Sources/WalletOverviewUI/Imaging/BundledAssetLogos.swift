import AppKit
import SwiftUI

/// In-bundle artwork for tokens we never want to depend on the network for.
/// Resolution walks every bundle layout the app might end up in: SwiftPM's
/// `Bundle.module`, the host app's main bundle, and the directory containing
/// the running executable. That covers raw `swift run`, Xcode-built debug
/// builds and the packaged .app produced by Scripts/package_app.sh.
enum BundledAssetLogos {
    static let sol: NSImage? = Self.load(name: "sol-logo", extension: "png")

    private static func load(name: String, extension ext: String) -> NSImage? {
        let bundleCandidates: [Bundle] = [.module, .main]
        for bundle in bundleCandidates {
            if let url = bundle.url(forResource: name, withExtension: ext),
               let image = NSImage(contentsOf: url)
            {
                return image
            }
        }
        let fileName = "\(name).\(ext)"
        let directoryCandidates: [URL] = [
            Bundle.main.bundleURL,
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 }
        for directory in directoryCandidates {
            let url = directory.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}

/// Native-SOL icon used wherever the portfolio row would otherwise show a
/// remote thumbnail. Renders the bundled PNG when present and falls back to
/// the original `◎` glyph in the unlikely case the resource is missing.
struct SOLLogo: View {
    var body: some View {
        if let image = BundledAssetLogos.sol {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.secondary.opacity(0.18))
                Text("◎")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

