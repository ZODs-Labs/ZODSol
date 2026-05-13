import AppKit
import SwiftUI

/// Reusable Select-style menu surface used to build dropdowns inside the
/// panel. Generic over the item type and row content so any list-of-pickables
/// can be hosted - directory pickers, asset pickers, network pickers, etc.
///
/// Visual language matches macOS Tahoe popovers: thin material card, hairline
/// separator stroke, soft drop shadow, and a snappy scale+fade transition
/// anchored to the top edge so it reads as "opening from the trigger".
///
/// Intended to be mounted as an `.overlay` so the surrounding form never
/// reflows when the menu opens or closes - same idiom Apple uses for
/// `NSPopUpButton` and `NSComboBox`.
struct SelectMenu<Item: Identifiable & Hashable, Row: View, Header: View>: View {
    /// External open flag. Wire to a `@FocusState`, `@State`, or any other
    /// source - the menu only renders content when this is `true`.
    let isOpen: Bool
    let items: [Item]
    let onSelect: (Item) -> Void
    let maxVisibleHeight: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let row: (Item, Bool) -> Row
    @ViewBuilder let header: () -> Header

    @State private var highlightedID: Item.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pre-scroll threshold. Up to this many items render as a natural-size
    /// stack so the menu sizes exactly to its content - no measurement, no
    /// flicker. Beyond it, a fixed-height `ScrollView` kicks in so the menu
    /// stays inside `maxVisibleHeight`.
    private var scrollThreshold: Int {
        5
    }

    init(
        isOpen: Bool,
        items: [Item],
        maxVisibleHeight: CGFloat = 184,
        cornerRadius: CGFloat = 10,
        onSelect: @escaping (Item) -> Void,
        @ViewBuilder row: @escaping (Item, Bool) -> Row,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() })
    {
        self.isOpen = isOpen
        self.items = items
        self.maxVisibleHeight = maxVisibleHeight
        self.cornerRadius = cornerRadius
        self.onSelect = onSelect
        self.row = row
        self.header = header
    }

    var body: some View {
        ZStack {
            if self.isOpen, !self.items.isEmpty {
                self.menu
                    .transition(Self.menuTransition)
            }
        }
        .animation(self.reduceMotion ? nil : Self.openAnimation, value: self.isOpen)
        .animation(self.reduceMotion ? nil : .smooth(duration: 0.18), value: self.items)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            let hdr = self.header()
            if Header.self != EmptyView.self {
                hdr
                Divider().opacity(0.35)
            }
            self.list
        }
        .background(
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(.thinMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 4)
        .onAppear { self.ensureHighlight() }
        .onChange(of: self.items) { _, _ in self.ensureHighlight() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var list: some View {
        if self.items.count <= self.scrollThreshold {
            self.rowStack
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    self.rowStack
                }
                .frame(height: self.maxVisibleHeight)
                .onChange(of: self.highlightedID) { _, newID in
                    guard let newID else { return }
                    withAnimation(self.reduceMotion ? nil : .smooth(duration: 0.16)) {
                        proxy.scrollTo(newID, anchor: nil)
                    }
                }
            }
        }
    }

    private var rowStack: some View {
        LazyVStack(spacing: 0) {
            ForEach(self.items) { item in
                Button {
                    self.onSelect(item)
                } label: {
                    self.row(item, self.highlightedID == item.id)
                }
                .buttonStyle(.plain)
                .id(item.id)
                .onHover { hovering in
                    if hovering {
                        self.highlightedID = item.id
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .padding(4)
    }

    private func ensureHighlight() {
        guard !self.items.isEmpty else {
            self.highlightedID = nil
            return
        }
        if let current = highlightedID, self.items.contains(where: { $0.id == current }) {
            return
        }
        self.highlightedID = self.items.first?.id
    }

    /// Asymmetric scale + fade. The opening curve is slightly larger so the
    /// menu "drops in" from the trigger; the closing curve barely shrinks so
    /// it feels like dismissal rather than collapse. Matches the timing curves
    /// AppKit uses for `NSMenu` and `NSPopover`.
    private static var menuTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top))
                .combined(with: .offset(y: -4)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
    }

    private static var openAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
    }
}

#if DEBUG

private struct PreviewItem: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
}

private struct SelectMenuPreviewHost: View {
    @State private var isOpen = true
    private let items: [PreviewItem] = (1...5).map {
        PreviewItem(id: $0, title: "Option \($0)", subtitle: "Subtitle for option \($0)")
    }

    var body: some View {
        VStack(spacing: 12) {
            Button(self.isOpen ? "Close menu" : "Open menu") { self.isOpen.toggle() }
                .buttonStyle(.borderedProminent)
            SelectMenu(
                isOpen: self.isOpen,
                items: self.items,
                onSelect: { _ in self.isOpen = false },
                row: { item, isHighlighted in
                    HStack(spacing: 10) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.callout.weight(.medium))
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHighlighted
                                ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
                                : Color.clear))
                },
                header: {
                    HStack {
                        Text("Header").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                })
                .frame(width: 320)
            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

#Preview("SelectMenu - generic") {
    SelectMenuPreviewHost()
}

#endif
