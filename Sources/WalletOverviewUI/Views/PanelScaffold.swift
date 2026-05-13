import SwiftUI

/// Three-zone layout shared by every panel route - fixed header, scrolling
/// middle, sticky footer. The scroll only engages when content overflows
/// (`scrollBounceBehavior(.basedOnSize)`), so panels that fit the 440 pt
/// window feel static and panels that overflow (expanded Details, long error
/// text, larger Dynamic Type) keep the primary action visible.
///
/// The header sits above the scroll with `zIndex(1)` so floating overlays
/// rendered inside it (the wallet picker dropdown, popovers) draw over the
/// content beneath without being clipped.
struct PanelScaffold<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer)
    {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 0) {
            self.header
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, PanelLayout.horizontalInset)
                .padding(.top, PanelLayout.headerTopInset)
                .padding(.bottom, PanelLayout.headerBottomInset)
                .zIndex(1)

            Divider().opacity(0.4)

            ScrollView {
                self.content
                    .padding(.horizontal, PanelLayout.horizontalInset)
                    .padding(.vertical, PanelLayout.contentVerticalInset)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider().opacity(0.4)

            self.footer
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PanelLayout.horizontalInset)
                .padding(.vertical, PanelLayout.footerVerticalInset)
        }
    }
}

/// Shared insets so every route lines up against the same grid. Sourced from
/// Apple's menu-bar utilities (Control Center, Battery): 16 pt outer margin,
/// 14 pt top, 10 pt bottom on the header, 10 pt vertical on the footer.
enum PanelLayout {
    static let horizontalInset: CGFloat = 16
    static let headerTopInset: CGFloat = 14
    static let headerBottomInset: CGFloat = 10
    static let contentVerticalInset: CGFloat = 12
    static let footerVerticalInset: CGFloat = 10
}
