import SwiftUI

/// Drop-in replacement for `ScrollView` that draws a thin pill-shaped
/// indicator at the trailing edge. The system scrollbar is hidden so the
/// panel's glass surface keeps its clean look; the custom thumb only fades
/// in while the content is scrolling and out shortly after, matching the
/// elegant motion of menu-bar utilities on macOS Tahoe.
///
/// `MinimalScrollView` is non-interactive on purpose. Trackpad gestures,
/// scroll wheels, keyboard arrows and `Page Up/Down` all still drive
/// scrolling through the underlying `ScrollView`; the thumb is purely an
/// indicator. Drop-in compatibility:
///
/// ```swift
/// MinimalScrollView {
///     VStack { ... }
/// }
/// ```
public struct MinimalScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let bounceBehavior: ScrollBounceBehavior
    private let content: Content

    @State private var contentSize: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var verticalOffset: CGFloat = 0
    @State private var isScrolling = false
    @State private var idleFadeTask: Task<Void, Never>?

    private let coordinateSpaceName = "MinimalScrollView"

    public init(
        _ axes: Axis.Set = .vertical,
        bounceBehavior: ScrollBounceBehavior = .basedOnSize,
        @ViewBuilder content: () -> Content)
    {
        self.axes = axes
        self.bounceBehavior = bounceBehavior
        self.content = content()
    }

    public var body: some View {
        ScrollView(self.axes) {
            self.content
                .background(self.contentMetricsReader)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(self.bounceBehavior)
        .coordinateSpace(name: self.coordinateSpaceName)
        .background(self.viewportMetricsReader)
        .overlay(alignment: .topTrailing) {
            MinimalScrollThumb(
                contentHeight: self.contentSize.height,
                viewportHeight: self.viewportSize.height,
                verticalOffset: self.verticalOffset,
                isActive: self.isScrolling)
                .allowsHitTesting(false)
                .padding(.trailing, 3)
                .padding(.vertical, 4)
        }
        .onPreferenceChange(ContentMetricsKey.self) { value in
            self.contentSize = value.size
            let newOffset = -value.minY
            if abs(newOffset - self.verticalOffset) > 0.5 {
                self.verticalOffset = newOffset
                self.flagScrolling()
            }
        }
        .onPreferenceChange(ViewportSizeKey.self) { size in
            self.viewportSize = size
        }
    }

    private var contentMetricsReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: ContentMetricsKey.self,
                value: ContentMetrics(
                    size: geometry.size,
                    minY: geometry.frame(in: .named(self.coordinateSpaceName)).minY))
        }
    }

    private var viewportMetricsReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ViewportSizeKey.self, value: geometry.size)
        }
    }

    private func flagScrolling() {
        self.isScrolling = true
        self.idleFadeTask?.cancel()
        self.idleFadeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self.isScrolling = false
        }
    }
}

/// Pill-shaped indicator pinned to the trailing edge. Sized as a fraction of
/// the viewport so a long list shows a short thumb and a barely overflowing
/// list shows a tall one, matching the visual heuristic in Apple's own
/// menu-bar surfaces.
private struct MinimalScrollThumb: View {
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let verticalOffset: CGFloat
    let isActive: Bool

    private let restingWidth: CGFloat = 3
    private let minimumThumbHeight: CGFloat = 24

    var body: some View {
        if self.shouldShow {
            Capsule(style: .continuous)
                .fill(.secondary.opacity(0.55))
                .frame(width: self.restingWidth, height: self.thumbHeight)
                .offset(y: self.thumbOffset)
                .opacity(self.isActive ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: self.isActive)
                .animation(.easeOut(duration: 0.12), value: self.thumbOffset)
        }
    }

    private var shouldShow: Bool {
        self.contentHeight > self.viewportHeight + 1 && self.viewportHeight > 0
    }

    private var thumbHeight: CGFloat {
        let ratio = self.viewportHeight / self.contentHeight
        let raw = self.viewportHeight * ratio
        return max(self.minimumThumbHeight, raw)
    }

    private var thumbOffset: CGFloat {
        let scrollable = max(self.contentHeight - self.viewportHeight, 1)
        let progress = min(max(self.verticalOffset / scrollable, 0), 1)
        let trackHeight = self.viewportHeight - self.thumbHeight
        return progress * max(trackHeight, 0)
    }
}

private struct ContentMetrics: Equatable {
    var size: CGSize
    var minY: CGFloat
}

private struct ContentMetricsKey: PreferenceKey {
    static let defaultValue = ContentMetrics(size: .zero, minY: 0)
    static func reduce(value: inout ContentMetrics, nextValue: () -> ContentMetrics) {
        value = nextValue()
    }
}

private struct ViewportSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
