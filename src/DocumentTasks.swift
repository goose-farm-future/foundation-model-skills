import Foundation
import NaturalLanguage
import PDFKit
import Vision

func csvCell(_ value: String) -> String {
    // Quote every cell, preserving commas, quotes and newlines exactly.
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// A PDF page's text layer, used to fill table cells exactly instead of from OCR (which misreads
/// "," as "." and "$" as "S"). PDFKit maps the cell's region to the characters inside it.
struct TextLayer {
    let page: PDFPage

    init?(_ page: PDFPage) {
        guard let text = page.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 else { return nil }
        self.page = page
    }

    /// Vision's cell boxes are tight and its table can start partway into the label column, so pad
    /// each cell and stretch the outer columns to the page edge on the same line.
    func text(in cell: NormalizedRect, firstColumn: Bool, lastColumn: Bool) -> String {
        let box = page.bounds(for: .mediaBox)
        var rect = cell.toImageCoordinates(box.size, origin: .lowerLeft).offsetBy(dx: box.minX, dy: box.minY).insetBy(dx: -1.5, dy: -1)
        if firstColumn { rect = CGRect(x: box.minX, y: rect.minY, width: rect.maxX - box.minX, height: rect.height) }
        if lastColumn { rect.size.width = box.maxX - rect.minX }
        return (page.selection(for: rect)?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

func tableTask(_ arguments: [String]) async throws {
    let options = try TaskOptions(arguments, values: ["--pages", "--max-pages"])
    let output = try options.required("--output")
    let urls = try inputFiles(options.input, extensions: imageExts.union(["pdf"]), excluding: output)
    let maxPages = try options.integer("--max-pages", default: Int.max)
    try await withNewDirectory(output) { staging, destination in
        var files: [[String: Any]] = [], sources: [[String: Any]] = []
        for (fileIndex, url) in urls.enumerated() {
            let (pages, total) = try loadPages(url, range: options.values["--pages"], maxPages: maxPages, needImages: true, forceOCR: true)
            let document = url.pathExtension.lowercased() == "pdf" ? PDFDocument(url: url) : nil
            var tableCount = 0
            for page in pages {
                guard let image = page.image else { continue }
                let layer = page.number > 0 ? document?.page(at: page.number - 1).flatMap(TextLayer.init) : nil
                let observations = try await RecognizeDocumentsRequest().perform(on: image)
                var index = 0
                for observation in observations {
                    for table in observation.document.tables {
                        index += 1; tableCount += 1
                        let cells = table.rows.flatMap { $0 }
                        let rows = (cells.map { $0.rowRange.upperBound }.max() ?? -1) + 1
                        let columns = (cells.map { $0.columnRange.upperBound }.max() ?? -1) + 1
                        var grid = Array(repeating: Array(repeating: "", count: columns), count: rows)
                        var spans: [[String: Any]] = [], seen: Set<String> = []
                        for cell in cells {
                            let key = "\(cell.rowRange.lowerBound):\(cell.columnRange.lowerBound)"
                            guard seen.insert(key).inserted else { continue }
                            let ocrText = cell.content.text.transcript
                            let exact = layer?.text(in: cell.content.boundingRegion.boundingBox, firstColumn: cell.columnRange.lowerBound == 0, lastColumn: cell.columnRange.upperBound == columns - 1) ?? ""
                            let value = exact.isEmpty ? ocrText : exact
                            grid[cell.rowRange.lowerBound][cell.columnRange.lowerBound] = value
                            spans.append(["row_start": cell.rowRange.lowerBound, "row_end": cell.rowRange.upperBound, "column_start": cell.columnRange.lowerBound, "column_end": cell.columnRange.upperBound, "text": value, "text_source": !exact.isEmpty ? "text layer" : ocrText.isEmpty ? "empty" : "ocr"])
                        }
                        let name = String(format: "%04d-page-%d-table-%d.csv", fileIndex + 1, max(1, page.number), index)
                        let csv = grid.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
                        try writeArtifact(Data(csv.utf8), to: staging.appendingPathComponent(name))
                        files.append(["source": url.path, "page": max(1, page.number), "output": destination.appendingPathComponent(name).path, "rows": rows, "columns": columns, "cells": spans])
                    }
                }
            }
            sources.append(["source": url.path, "pages_processed": pages.map { max(1, $0.number) }, "total_pages": total, "tables": tableCount])
        }
        return ["files": files, "sources": sources, "note": "Zero-based inclusive cell spans; merged text appears in the top-left CSV cell. Cells with text_source \"text layer\" are copied exactly from the PDF; \"ocr\" cells may misread characters. CSV contains literal source text, including formula-like text."]
    }
}

func searchTask(_ arguments: [String]) throws {
    let options = try TaskOptions(arguments, values: ["--query", "--limit", "--language", "--pages", "--max-pages"], flags: ["--lexical", "--force-ocr"])
    guard options.input != "-" else { throw ToolError.usage("local-search needs a file or folder") }
    let query = try options.required("--query").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { throw ToolError.usage("--query must not be blank") }
    let limit = try options.integer("--limit", default: 5, maximum: 100)
    let language = NLLanguage(rawValue: options.values["--language"] ?? "en")
    let embedding = options.flags.contains("--lexical") ? nil : NLEmbedding.sentenceEmbedding(for: language)
    let queryVector = embedding?.vector(for: query)
    let stop: Set<String> = ["a", "an", "the", "is", "are", "was", "were", "in", "on", "of", "for", "and", "to", "when", "what", "where", "does", "do", "how"]
    func words(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !stop.contains($0) })
    }
    func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let norms = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
        return norms > 0 ? dot / norms : 0
    }
    let terms = words(query)
    let units = try textUnits(options)
    var candidates: [(Double, Int, [String: Any])] = []
    var passages = 0
    for unit in units {
        // Overlapping passages retain neighboring evidence and source line references.
        let lines = unit.text.components(separatedBy: "\n")
        var start = 0
        while start < lines.count {
            var end = start, length = 0
            while end < lines.count && end - start < 12 && length < 1600 { length += lines[end].count + 1; end += 1 }
            let passage = lines[start..<end].joined(separator: "\n")
            // Long single lines are split rather than silently truncated.
            let characters = Array(passage)
            for offset in stride(from: 0, to: characters.count, by: 1600) {
                let text = String(characters[offset..<min(offset + 1600, characters.count)])
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let lexical = terms.isEmpty ? 0 : Double(words(text).intersection(terms).count) / Double(terms.count)
                let semantic = queryVector.flatMap { q in embedding?.vector(for: text).map { cosine(q, $0) } } ?? 0
                let score = queryVector == nil ? lexical : lexical * 0.55 + max(0, semantic) * 0.45
                passages += 1
                if score > 0 {
                    var row = unit.reference
                    row["line_start"] = unit.line + start + characters[..<offset].filter { $0 == "\n" }.count
                    row["line_end"] = unit.line + start + characters[..<min(offset + 1600, characters.count)].filter { $0 == "\n" }.count
                    row["passage_character_offset"] = offset
                    row["text"] = text; row["score"] = score
                    candidates.append((score, passages, row))
                }
            }
            if end == lines.count { break }
            start = max(start + 1, end - 2)
        }
    }
    let matches = candidates.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 > $1.0 }.prefix(limit).map { $0.2 }
    try emit(["query": query, "engine": queryVector == nil ? "lexical" : "Apple NaturalLanguage sentence embeddings + lexical", "sources_scanned": Set(units.map(\.source)).count, "passages_scanned": passages, "matches": matches, "note": "Ranked source passages, not generated answers. Ranking scores are not probabilities; an absent match is not proof that a fact is absent."], options: options, count: matches.count)
}
