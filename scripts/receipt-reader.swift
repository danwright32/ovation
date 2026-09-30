// The Vision half of scripts/measure-receipt-reads.py, ovation#74.
//
// It reads each image it is given with Apple's on device text recognition and
// barcode detection, and writes what Vision saw as JSON into a file for the
// Python half to interpret. Nothing here decides what the amount, the date or
// the vendor is; that is interpretation, and it lives in one place, the Python
// half, where the output privacy suite can drive it on any machine.
//
// NEVER A NETWORK SERVICE. Vision runs on the Mac, and the images are Dan's
// real receipts (docs/PRIVACY-FLOOR.md).
//
// THE READINGS GO TO THE FILE NAMED BY --out, NEVER STDOUT. They carry receipt
// text, so the only thing allowed to read them is the Python half, which writes
// them into the custody folder and prints counts. And stdout is not this
// program's alone: in a virtual machine Apple's model runtime prints its own
// exceptions there, which spoiled the JSON on CI (2026-09-30). Anything written to stderr names a receipt by its
// position, never its filename or its content, because stderr does reach the
// terminal.
//
// Usage: swiftc -O -o reader receipt-reader.swift && reader --out <file> <image>...

import CoreGraphics
import Foundation
import ImageIO
import Vision

// PINNED, and recorded with every result, because Vision is supplied by the
// operating system and changes under a system update with no code change, so a
// number is only meaningful beside the revision it was read with (PRD 18c).
let textRevision = VNRecognizeTextRequestRevision3
let barcodeRevision = VNDetectBarcodesRequestRevision4
// How many readings of each piece of text to keep. The alternatives are the
// ambiguity signal PRD 18a names in place of a second reader, so they are kept
// rather than only the best one.
let candidatesPerObservation = 5

struct Candidate: Encodable {
    let text: String
    let confidence: Float
}

struct Observation: Encodable {
    let candidates: [Candidate]
    // The four corners of the text, normalised with the origin bottom left, as
    // [x, y]. Corners rather than a box, because Vision reads a sideways or
    // skewed receipt without being told its orientation (measured 2026-09-29:
    // text revision 3 read a receipt turned 90 degrees exactly as it read the
    // upright one, with every orientation hint scoring the same), and reports
    // each box in the image's own frame. The direction the text runs is what
    // says which way is up, and only the corners carry it.
    let topLeft: [Double]
    let topRight: [Double]
    let bottomLeft: [Double]
    let bottomRight: [Double]
}

struct Barcode: Encodable {
    let symbology: String
    let payload: String?
}

struct Receipt: Encodable {
    let index: Int
    let readable: Bool
    let pixelWidth: Int
    let pixelHeight: Int
    let observations: [Observation]
    let observationsWithCorrection: [Observation]
    let barcodes: [Barcode]
    let error: String?
    // True when Vision itself refused, which is a fact about the machine rather
    // than the image, so the probe answers CANNOT MEASURE instead of blaming the
    // receipt (ovation#636 CI).
    var visionRefused: Bool = false
}

struct Output: Encodable {
    let osVersion: String
    let textRecognitionRevision: Int
    let barcodeRevision: Int
    let receipts: [Receipt]
}

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          CGImageSourceGetCount(source) > 0 else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

// TWO PASSES, and the second is not a second reader. The first has language
// correction OFF, because correction "corrects" digits toward words and a digit
// is the field that matters most (Downbeat's questionnaire reader chose the
// same). But measured on 2026-09-29, with correction off text revision 3 offers
// exactly ONE candidate per observation, every time, on clean and degraded
// images alike, so PRD 18a's alternative readings cannot exist in that pass.
// With correction on it offers several. So both passes are read and recorded,
// and the second is counted as corroboration by the SAME reader, never as an
// independent check (ovation#74, candidate 1).
func recognise(_ image: CGImage, correcting: Bool) throws -> [Observation] {
    let request = VNRecognizeTextRequest()
    request.revision = textRevision
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = correcting
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    return (request.results ?? []).map { observation in
        Observation(
            candidates: observation.topCandidates(candidatesPerObservation).map {
                Candidate(text: $0.string, confidence: $0.confidence)
            },
            topLeft: point(observation.topLeft), topRight: point(observation.topRight),
            bottomLeft: point(observation.bottomLeft), bottomRight: point(observation.bottomRight)
        )
    }
}

func point(_ p: CGPoint) -> [Double] { [Double(p.x), Double(p.y)] }

func detectBarcodes(_ image: CGImage) throws -> [Barcode] {
    let request = VNDetectBarcodesRequest()
    request.revision = barcodeRevision
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    return (request.results ?? []).map {
        Barcode(symbology: $0.symbology.rawValue, payload: $0.payloadStringValue)
    }
}

func read(_ path: String, index: Int) -> Receipt {
    guard let image = loadImage(path) else {
        return Receipt(index: index, readable: false, pixelWidth: 0, pixelHeight: 0,
                       observations: [], observationsWithCorrection: [], barcodes: [], error: "not decodable as an image")
    }
    do {
        return Receipt(index: index, readable: true, pixelWidth: image.width, pixelHeight: image.height,
                       observations: try recognise(image, correcting: false),
                       observationsWithCorrection: try recognise(image, correcting: true),
                       barcodes: try detectBarcodes(image), error: nil)
    } catch {
        // Vision refusing is recorded as a refusal, never as a receipt with no
        // text on it, which would read as a real result of zero (L215).
        return Receipt(index: index, readable: false, pixelWidth: image.width, pixelHeight: image.height,
                       observations: [], observationsWithCorrection: [], barcodes: [],
                       error: "Vision refused: \(error.localizedDescription)", visionRefused: true)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 3, arguments[0] == "--out" else {
    FileHandle.standardError.write(Data("usage: receipt-reader --out <file> <image>...\n".utf8))
    exit(64)
}
let outPath = arguments[1]
let paths = Array(arguments.dropFirst(2))

let output = Output(
    osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
    textRecognitionRevision: textRevision,
    barcodeRevision: barcodeRevision,
    receipts: paths.enumerated().map { read($0.element, index: $0.offset + 1) }
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
do {
    try encoder.encode(output).write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("could not encode or write the readings: \(error.localizedDescription)\n".utf8))
    exit(1)
}
