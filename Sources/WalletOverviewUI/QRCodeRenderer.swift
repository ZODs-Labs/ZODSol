import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

public enum QRCodeRenderer {
    public enum CorrectionLevel: String, Sendable {
        case low = "L"
        case medium = "M"
        case quartile = "Q"
        case high = "H"
    }

    public nonisolated static func render(
        payload: String,
        foreground: CGColor,
        background: CGColor,
        sizeInPixels: Int,
        correctionLevel: CorrectionLevel = .high
    ) async -> NSImage? {
        guard !payload.isEmpty, sizeInPixels > 0 else { return nil }
        guard let data = payload.data(using: .utf8) else { return nil }

        let generator = CIFilter.qrCodeGenerator()
        generator.message = data
        generator.setValue(correctionLevel.rawValue, forKey: "inputCorrectionLevel")

        guard let qrImage = generator.outputImage else { return nil }

        let colorizer = CIFilter.falseColor()
        colorizer.inputImage = qrImage
        colorizer.color0 = CIColor(cgColor: foreground)
        colorizer.color1 = CIColor(cgColor: background)

        guard let coloredImage = colorizer.outputImage else { return nil }
        let extent = coloredImage.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        let scale = CGFloat(sizeInPixels) / extent.width
        let scaledImage = coloredImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        let backingScale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }
        let pointSize = CGFloat(sizeInPixels) / backingScale
        return NSImage(cgImage: cgImage, size: NSSize(width: pointSize, height: pointSize))
    }
}
