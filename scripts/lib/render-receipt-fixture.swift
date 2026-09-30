// Draws a SYNTHETIC receipt image for scripts/test-measure-receipt-reads.sh.
//
// ovation#74. The probe it tests reads Dan's real photographed receipts, which
// are custody data and can never be a fixture (docs/PRIVACY-FLOOR.md). So every
// receipt the suite reads is drawn here, from a spec the suite writes, with an
// invented vendor. Nothing here reads a real receipt.
//
// Usage: swift render-receipt-fixture.swift <spec.txt> <out.png>
//
// The spec is one row per line, fields separated by a tab:
//
//     C<TAB>text               a centred line (the vendor, an address)
//     L<TAB>left<TAB>right     a label on the left and an amount on the right
//     QR<TAB>payload           a QR code carrying payload, drawn centred
//
// It refuses a row it does not understand rather than skipping it, because a
// fixture that silently lost its TOTAL line would test a different receipt
// from the one the suite describes (L165).

import AppKit
import CoreImage
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: render-receipt-fixture <spec.txt> <out.png>\n".utf8))
    exit(64)
}

enum Row {
    case centred(String)
    case pair(String, String)
    case qr(String)
}

let spec: String
do {
    spec = try String(contentsOfFile: arguments[1], encoding: .utf8)
} catch {
    FileHandle.standardError.write(Data("cannot read the spec: \(error)\n".utf8))
    exit(1)
}

var rows: [Row] = []
for (index, line) in spec.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    switch (fields.first, fields.count) {
    case ("C", 2): rows.append(.centred(fields[1]))
    case ("L", 3): rows.append(.pair(fields[1], fields[2]))
    case ("QR", 2): rows.append(.qr(fields[1]))
    default:
        FileHandle.standardError.write(Data("spec line \(index + 1) is not a row this renderer draws\n".utf8))
        exit(1)
    }
}

let width = 900
let lineHeight = 56
let qrSide = 220
let margin = 60
var height = margin * 2
for row in rows {
    if case .qr = row { height += qrSide + 20 } else { height += lineHeight }
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("cannot create a drawing context\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

let font = NSFont(name: "Helvetica", size: 30) ?? NSFont.systemFont(ofSize: 30)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]

// AppKit's origin is bottom left, so rows are laid from the top down.
var top = height - margin
for row in rows {
    switch row {
    case .centred(let text):
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: (Double(width) - size.width) / 2, y: Double(top - lineHeight + 12)))
        top -= lineHeight
    case .pair(let left, let right):
        NSAttributedString(string: left, attributes: attributes)
            .draw(at: NSPoint(x: margin, y: top - lineHeight + 12))
        let string = NSAttributedString(string: right, attributes: attributes)
        string.draw(at: NSPoint(x: Double(width - margin) - string.size().width, y: Double(top - lineHeight + 12)))
        top -= lineHeight
    case .qr(let payload):
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            FileHandle.standardError.write(Data("no QR generator on this Mac\n".utf8))
            exit(1)
        }
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: output.extent) else {
            FileHandle.standardError.write(Data("the QR generator drew nothing\n".utf8))
            exit(1)
        }
        let rect = NSRect(x: (width - qrSide) / 2, y: top - qrSide - 10, width: qrSide, height: qrSide)
        context.imageInterpolation = .none
        context.cgContext.interpolationQuality = .none
        context.cgContext.draw(cg, in: rect)
        top -= qrSide + 20
    }
}
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("cannot encode the PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: arguments[2]))
} catch {
    FileHandle.standardError.write(Data("cannot write the PNG: \(error)\n".utf8))
    exit(1)
}
