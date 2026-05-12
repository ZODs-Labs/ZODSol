import AppKit
import SwiftUI

/// Translucent surface used as `NSPanel.contentView` so the panel picks up a
/// live blur of whatever is behind the window — the native Liquid Glass look
/// on macOS 26, and a `popover`-material NSVisualEffectView fallback on
/// earlier macOS releases.
@MainActor
final class GlassPanelView: NSView {
    private let cornerRadius: CGFloat
    private weak var contentHost: NSView?

    init(size: NSSize, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: NSRect(origin: .zero, size: size))
        self.autoresizingMask = [.width, .height]
        self.wantsLayer = true
        // Round the contentView's own layer with masksToBounds so NSPanel's
        // auto shadow follows the rounded silhouette. Without this the panel
        // computes its shadow from the rectangular layer bounds and a
        // squared-off ghost is visible behind the rounded glass.
        self.layer?.cornerRadius = cornerRadius
        self.layer?.cornerCurve = .continuous
        self.layer?.masksToBounds = true

        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let opaque = NSView(frame: self.bounds)
            opaque.autoresizingMask = [.width, .height]
            opaque.wantsLayer = true
            opaque.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            opaque.layer?.cornerRadius = cornerRadius
            opaque.layer?.cornerCurve = .continuous
            opaque.layer?.masksToBounds = true
            self.addSubview(opaque)
            self.contentHost = opaque
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: self.bounds)
            glass.autoresizingMask = [.width, .height]
            // `.regular` matches Apple's native menu-bar panels (Battery,
            // Wi-Fi, Control Center): a glass blur of what is behind, opaque
            // enough that content over it stays legible. `.clear` is Apple's
            // most see-through Liquid Glass variant and goes washed-out on
            // focus, wrong for a text-entry panel. NOTE: every Liquid Glass
            // style still re-renders when the host window flips between
            // non-key and key, so the panel must be opened already key
            // (see StatusItemController.togglePanel) to avoid a visible
            // background "jump" on the first click.
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            self.addSubview(glass)
            self.contentHost = glass
        } else {
            let effect = NSVisualEffectView(frame: self.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.isEmphasized = false
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            self.addSubview(effect)
            self.contentHost = effect
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Embed `content` inside the glass. On macOS 26 this is set via the
    /// glass view's `contentView` (z-order is owned by `NSGlassEffectView`);
    /// on earlier releases the content is added as a sized subview.
    func install(content: NSView) {
        if #available(macOS 26.0, *), let glass = contentHost as? NSGlassEffectView {
            glass.contentView = content
            return
        }
        guard let host = contentHost else { return }
        content.frame = host.bounds
        content.autoresizingMask = [.width, .height]
        host.addSubview(content)
    }
}

/// Hosting view that opts its SwiftUI subtree into AppKit vibrancy so text and
/// shapes blend correctly against the glass background.
@MainActor
final class VibrantHostingView<Content: View>: NSHostingView<Content> {
    override var allowsVibrancy: Bool {
        true
    }
}
