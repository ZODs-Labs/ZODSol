import AppKit
import SwiftUI

struct ShareButton: View {
    let itemsProvider: @MainActor () -> [Any]
    @State private var present = false

    init(itemsProvider: @MainActor @escaping () -> [Any]) {
        self.itemsProvider = itemsProvider
    }

    init(items: [String]) {
        self.itemsProvider = { items }
    }

    var body: some View {
        Button {
            self.present = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Share")
        .help("Share")
        .background(SharePickerHost(itemsProvider: self.itemsProvider, isPresented: self.$present))
    }
}

private struct SharePickerHost: NSViewRepresentable {
    let itemsProvider: @MainActor () -> [Any]
    @Binding var isPresented: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard self.isPresented else { return }
        let provider = self.itemsProvider
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: provider())
            picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            self.isPresented = false
        }
    }
}
