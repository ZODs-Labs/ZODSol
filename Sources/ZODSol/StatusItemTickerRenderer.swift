import AppKit
import Formatters
import WalletOverviewUI

/// Turns the AppKit-free `TickerRenderModel` into the status item's
/// `attributedTitle` and its VoiceOver label. Uses menu-bar-sized monospaced
/// digits so the width does not jitter as prices change, and appearance-aware
/// system colors so the bar reads correctly in light and dark menu bars.
enum StatusItemTickerRenderer {
    static func attributedTitle(for model: TickerRenderModel) -> NSAttributedString? {
        guard case let .ticker(segments) = model, !segments.isEmpty else { return nil }
        let font = self.tickerFont
        let result = NSMutableAttributedString()
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            }
            result.append(self.render(segment, font: font))
        }
        return result
    }

    static func accessibilityLabel(for model: TickerRenderModel) -> String? {
        guard case let .ticker(segments) = model, !segments.isEmpty else { return nil }
        return segments.map { segment in
            var parts: [String] = []
            if let symbol = segment.symbol { parts.append(symbol) }
            parts.append(segment.priceText)
            if let change = segment.changeText { parts.append("change \(change)") }
            return parts.joined(separator: " ")
        }
        .joined(separator: ", ")
    }

    private static var tickerFont: NSFont {
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private static func render(_ segment: TickerRenderSegment, font: NSFont) -> NSAttributedString {
        let primary: NSColor = segment.isDimmed ? .secondaryLabelColor : .labelColor
        let line = NSMutableAttributedString()
        if let symbol = segment.symbol {
            line.append(NSAttributedString(
                string: "\(symbol) ",
                attributes: [.font: font, .foregroundColor: primary]))
        }
        line.append(NSAttributedString(
            string: segment.priceText,
            attributes: [.font: font, .foregroundColor: primary]))
        if let changeText = segment.changeText {
            line.append(NSAttributedString(
                string: " \(changeText)",
                attributes: [.font: font, .foregroundColor: self.color(for: segment.tint, dimmed: segment.isDimmed)]))
        }
        return line
    }

    private static func color(for tint: PercentageDeltaFormatter.DeltaColor, dimmed: Bool) -> NSColor {
        let base: NSColor = switch tint {
        case .up: .systemGreen
        case .down: .systemRed
        case .neutral: .secondaryLabelColor
        }
        return dimmed ? base.withAlphaComponent(0.6) : base
    }
}
