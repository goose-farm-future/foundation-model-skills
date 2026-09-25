// fm: on-device image/PDF analysis with Apple Vision (OCR) and Apple Foundation Models
// (image understanding). Part of foundation-model-skills. Nothing leaves the Mac.

import CoreGraphics
import Foundation
import FoundationModels
import ImageIO
import PDFKit
import Speech
import Vision

struct Page {
    let number: Int      // 1-based; 0 for single images
    let image: CGImage?  // nil when a PDF page has a usable text layer and no image is needed
    let embeddedText: String?
}

enum ToolError: Error, CustomStringConvertible {
    case usage(String), unreadable(String)
    var description: String {
        switch self {
        case .usage(let m): return m
        case .unreadable(let m): return "error: \(m)"
        }
    }
}

let usage = """
usage: fm <command> <file> [options]

  pdf-to-text    <file.pdf>  [--pages N|N-M] [--max-pages N] [--force-ocr]
                 Exact text. Uses the PDF text layer when present, Apple Vision OCR otherwise.
                 --force-ocr ignores the text layer and OCRs the rendered page (annotations,
                 stamps, e-signature fields, handwriting).
  ocr            <image|pdf> [--pages N|N-M]
                 Exact text via Apple Vision OCR of the pixels. For PDFs, every page is
                 rendered and OCR'd, ignoring any text layer.
  describe-image <image|pdf> [--pages N|N-M]
                 On-device Foundation Model describes the image, grounded with OCR text.
  ask-image      <image|pdf> "<question>" [--pages N|N-M]
                 On-device Foundation Model answers a question about the image.
  doctor         Report whether Vision and the on-device model are available.
"""

// MARK: - Image loading

/// Draws onto an opaque white RGB canvas. Transparent PNGs otherwise read as solid black.
func flatten(_ img: CGImage, maxSide: Int? = nil) -> CGImage {
    var w = img.width, h = img.height
    if let maxSide, max(w, h) > maxSide {
        let s = Double(maxSide) / Double(max(w, h))
        w = Int(Double(w) * s); h = Int(Double(h) * s)
    }
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func render(_ page: PDFPage, scale: CGFloat = 2.5) -> CGImage {
    let box = page.bounds(for: .mediaBox)
    let w = Int(box.width * scale), h = Int(box.height * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    return ctx.makeImage()!
}

func parseRange(_ s: String?, count: Int, maxPages: Int) throws -> [Int] {
    guard count > 0 else { throw ToolError.unreadable("PDF has no readable pages") }
    guard maxPages > 0 else { throw ToolError.usage("--max-pages must be positive") }
    guard let s else { return Array(1...min(count, maxPages)) }
    let raw = s.split(separator: "-", omittingEmptySubsequences: false)
    let parts = raw.compactMap { Int($0) }
    guard (1...2).contains(raw.count), raw.count == parts.count, let lo = parts.first,
          lo > 0, lo <= count, (parts.last ?? lo) >= lo else { throw ToolError.usage("invalid page range: \(s); PDF has \(count) pages") }
    let hi = min(count, parts.last ?? lo)
    return Array(lo...hi)
}

func loadPages(_ url: URL, range: String?, maxPages: Int, needImages: Bool, forceOCR: Bool) throws -> (pages: [Page], total: Int) {
    if url.pathExtension.lowercased() == "pdf" {
        guard let doc = PDFDocument(url: url) else { throw ToolError.unreadable("cannot open PDF \(url.path)") }
        guard !doc.isLocked else { throw ToolError.unreadable("PDF is locked: \(url.path)") }
        let pages = try parseRange(range, count: doc.pageCount, maxPages: maxPages).compactMap { n -> Page? in
            guard let p = doc.page(at: n - 1) else { return nil }
            let text = p.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            // A real text layer is exact; only rasterise when it's missing/thin or the model needs pixels.
            let hasText = !forceOCR && (text?.count ?? 0) > 40
            return Page(number: n, image: (needImages || !hasText) ? render(p) : nil,
                        embeddedText: hasText ? text : nil)
        }
        return (pages, doc.pageCount)
    }
    return ([Page(number: 0, image: flatten(try loadImage(url)), embeddedText: nil)], 1)
}

func loadImage(_ url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let raw = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    else { throw ToolError.unreadable("cannot decode image \(url.path)") }
    var img = raw
    // Respect EXIF orientation (phone photos) by asking ImageIO for a transformed thumbnail at full size.
    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let o = props[kCGImagePropertyOrientation] as? UInt32, o != 1,
       let t = CGImageSourceCreateThumbnailAtIndex(src, 0, [
           kCGImageSourceCreateThumbnailFromImageAlways: true,
           kCGImageSourceCreateThumbnailWithTransform: true,
           kCGImageSourceThumbnailMaxPixelSize: max(raw.width, raw.height)] as CFDictionary) {
        img = t
    }
    return img
}

// MARK: - OCR (Apple Vision)

/// Vision clips glyphs touching the border and misses small text, so pad and upscale first.
func prepareForOCR(_ img: CGImage) -> CGImage {
    let scale = max(1.0, min(3.0, 2000.0 / Double(max(img.width, img.height))))
    let w = Int(Double(img.width) * scale), h = Int(Double(img.height) * scale)
    let pad = max(w, h) / 25
    let ctx = CGContext(data: nil, width: w + 2 * pad, height: h + 2 * pad, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w + 2 * pad, height: h + 2 * pad))
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: pad, y: pad, width: w, height: h))
    return ctx.makeImage()!
}

func ocr(_ img: CGImage) throws -> String {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    req.automaticallyDetectsLanguage = true
    try VNImageRequestHandler(cgImage: prepareForOCR(img)).perform([req])
    let obs = (req.results ?? []).filter { !($0.topCandidates(1).first?.string.isEmpty ?? true) }
    // Group into visual lines (Vision's origin is bottom-left), then left-to-right within a line.
    let sorted = obs.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    var lines: [[VNRecognizedTextObservation]] = []
    for o in sorted {
        if let last = lines.last?.first, abs(last.boundingBox.midY - o.boundingBox.midY) < last.boundingBox.height * 0.5 {
            lines[lines.count - 1].append(o)
        } else {
            lines.append([o])
        }
    }
    return lines.map { line in
        line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "   ")
    }.joined(separator: "\n")
}

func pageText(_ p: Page) throws -> String {
    if let t = p.embeddedText { return t }
    guard let img = p.image else { return "" }
    return try ocr(img)
}

// MARK: - Foundation Model

func askModel(image: CGImage, ocrText: String, question: String) async throws -> String {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
        throw ToolError.unreadable("Apple Intelligence model unavailable: \(model.availability)")
    }
    let instructions = """
    You analyse images for another AI assistant. Be precise and factual. Describe only what is visible. \
    When OCR text is supplied, treat it as the authoritative source for exact characters, numbers and \
    spelling; use the image for layout, visuals and context. Never guess or invent values: if the answer \
    is not visible in the image or OCR text, reply that it is not visible.
    """
    let small = flatten(image, maxSide: 1536)
    // The on-device context window is small, so trim long OCR text rather than fail.
    for limit in [6000, 2500, 0] {
        let grounding = ocrText.isEmpty ? "\n\n(OCR detected no text in this image.)" : limit == 0 ? "" :
            "\n\nOCR text from the image (authoritative for exact characters):\n\"\"\"\n\(ocrText.prefix(limit))\n\"\"\""
        let session = LanguageModelSession(instructions: instructions)
        do {
            let r = try await session.respond { Attachment(small); question + grounding }
            return r.content
        } catch LanguageModelError.contextSizeExceeded {
            continue
        }
    }
    throw ToolError.unreadable("image + prompt exceed the on-device context window")
}

// MARK: - Main

let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp"]

@main
struct FM {
    static func main() async {
        do { try await run() } catch {
            FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func doctor() async {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let model = SystemLanguageModel.default
        print("macOS \(v.majorVersion).\(v.minorVersion)")
        print("on-device model: \(model.availability)")
        print("image input: \(model.capabilities.contains(.vision) ? "supported" : "not supported")")
        print("OCR (Apple Vision): available")
        if case .available = model.availability { print("model context: \(model.contextSize) tokens") }
        print("on-device speech: \(SpeechTranscriber.isAvailable ? "available" : "unavailable")")
        print("installed speech locales: \(await SpeechTranscriber.installedLocales.map(\.identifier).joined(separator: ", "))")
        let segmentation = GenerateIterativeSegmentationRequest(seedPoint: NormalizedPoint(x: 0.5, y: 0.5))
        print("segmentation assets: \(await segmentation.assetStatus)")
    }

    static func run() async throws {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "--help" || args.first == "help" { print(usage + "\n\n" + localUsage); return }
        if let command = args.first, localCommands.contains(command) { return try await runLocalTask(command, arguments: Array(args.dropFirst())) }
        func take(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            defer { args.removeSubrange(i...(i + 1)) }
            return args[i + 1]
        }
        let range = take("--pages")
        let maximum = take("--max-pages") ?? "30"
        guard let maxPages = Int(maximum), maxPages > 0 else { throw ToolError.usage("--max-pages must be a positive integer") }
        var forceOCR = args.contains("--force-ocr")
        args.removeAll { $0 == "--force-ocr" }
        if args.first == "doctor" { return await doctor() }
        guard args.count >= 2 else { throw ToolError.usage(usage) }
        let command = args[0]
        let url = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ToolError.unreadable("no such file: \(url.path)") }
        let ext = url.pathExtension.lowercased()

        let question: String?
        switch command {
        case "pdf-to-text":
            guard ext == "pdf" else { throw ToolError.usage("pdf-to-text expects a .pdf; use ocr for images") }
            question = nil
        case "ocr":
            guard imageExts.contains(ext) || ext == "pdf" else { throw ToolError.usage("ocr expects an image or PDF") }
            forceOCR = true
            question = nil
        case "describe-image":
            question = "Describe this image in detail: what it is, its layout, key content, and any charts, tables, UI or notable visual elements."
        case "ask-image":
            guard args.count >= 3 else { throw ToolError.usage(usage) }
            question = args[2]
        default: throw ToolError.usage(usage)
        }
        // Vision commands are about what is visible, so ground them with OCR of the rendered
        // page, not the PDF text layer (which can omit filled-in fields and annotations).
        if question != nil { forceOCR = true }

        let (pages, total) = try loadPages(url, range: range, maxPages: maxPages, needImages: question != nil, forceOCR: forceOCR)
        let multi = pages.count > 1 || total > 1
        print("<!-- fm \(command) · \(url.lastPathComponent)\(multi ? " · pages \(pages.first?.number ?? 0)-\(pages.last?.number ?? 0) of \(total)" : "") · on-device -->")

        for p in pages {
            if multi { print("\n## Page \(p.number)\(p.embeddedText != nil ? " (text layer)" : " (OCR)")\n") }
            let text = try pageText(p)
            if let question, let img = p.image {
                print(try await askModel(image: img, ocrText: text, question: question))
            } else {
                print(text.isEmpty ? "[no text detected]" : text)
            }
        }
        if total > pages.count && range == nil {
            print("\n<!-- \(total - pages.count) more pages not processed; use --pages N-M -->")
        }
    }
}
