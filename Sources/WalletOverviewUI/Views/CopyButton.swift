import AppKit
import SwiftUI

struct CopyButton: View {
    let text: String
    let onCopy: (@MainActor () -> Void)?
    @State private var copied = false

    init(text: String, onCopy: (@MainActor () -> Void)? = nil) {
        self.text = text
        self.onCopy = onCopy
    }

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(self.text, forType: .string)
            self.copied = true
            self.onCopy?()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.copied = false
            }
        } label: {
            Image(systemName: self.copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Copy")
        .help("Copy to clipboard")
    }
}

#if DEBUG

#Preview("CopyButton") {
    CopyButton(text: "So11111111111111111111111111111111111111112")
        .padding()
        .frame(width: 120)
}

#endif
