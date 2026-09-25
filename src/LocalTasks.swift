import Foundation
import FoundationModels

let localCommands: Set<String> = ["table-to-csv", "extract", "condense", "classify", "local-search", "transcribe-audio", "translate", "image-cutout"]

let localUsage = """
Local tasks (no API fees; macOS 27+, Apple silicon):
  fm table-to-csv <image|pdf|folder> --output <new-folder> [--pages N-M]
  fm extract <file|folder|-> --fields name,date,total [--output result.json]
  fm extract <file|folder|-> --schema fields.json [--output result.json]
  fm condense <log|-> [--output result.json] [--max-lines 200] [--explain]
  fm classify <file|folder|-> [--labels bug,feature,other] [--lines] [--output result.json]
  fm local-search <file|folder> --query "question" [--limit 5] [--output result.json]
  fm transcribe-audio <audio|video> [--locale en-US] [--format json|txt|vtt] [--output file]
  fm translate <text|json|folder> --source en --target es --output <new-folder>
  fm image-cutout <image> --point x,y|--box x,y,w,h --output cutout.png [--mask mask.png]

Coordinates are normalized 0...1, origin TOP LEFT. Output files are not overwritten
unless --overwrite is supplied. Output folders must be new. --output returns a compact
manifest; without it JSON goes to stdout. Speech and cutout accept --download-assets
to install Apple's model assets. Input content is always processed on-device.
extract schemas are JSON objects mapping field names to descriptions; values are
copied strings or null, with verified source quotes and explicit conflicting values.
"""

struct TaskOptions {
    var input: String
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: [String], values allowed: Set<String> = [], flags flagNames: Set<String> = []) throws {
        var positional: [String] = []
        var i = 0
        let valueNames = allowed.union(["--output"])
        let flagNames = flagNames.union(["--overwrite"])
        while i < args.count {
            let arg = args[i]
            if valueNames.contains(arg) {
                guard i + 1 < args.count, !args[i + 1].hasPrefix("--"), values[arg] == nil else {
                    throw ToolError.usage("\(arg) needs one value and may appear only once")
                }
                values[arg] = args[i + 1]; i += 2
            } else if flagNames.contains(arg) {
                flags.insert(arg); i += 1
            } else if arg.hasPrefix("--") {
                throw ToolError.usage("unknown option: \(arg)\n\(localUsage)")
            } else {
                positional.append(arg); i += 1
            }
        }
        guard positional.count == 1 else { throw ToolError.usage(localUsage) }
        input = positional[0]
        if let output = values["--output"] {
            try validateOutput(pathURL(output), inputs: input == "-" ? [] : [pathURL(input)], overwrite: flags.contains("--overwrite"))
        }
    }

    func required(_ key: String) throws -> String {
        guard let value = values[key], !value.isEmpty else { throw ToolError.usage("\(key) is required") }
        return value
    }

    func integer(_ key: String, default fallback: Int, maximum: Int = Int.max) throws -> Int {
        guard let value = values[key] else { return fallback }
        guard let n = Int(value), n > 0, n <= maximum else { throw ToolError.usage("\(key) must be between 1 and \(maximum)") }
        return n
    }
}

func pathURL(_ path: String) -> URL {
    URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
}

func validateOutput(_ url: URL, inputs: [URL], overwrite: Bool) throws {
    let resolved = url.resolvingSymlinksInPath()
    func sameFile(_ input: URL) -> Bool {
        if input.resolvingSymlinksInPath() == resolved { return true }
        // Also protect hard links and case aliases on a case-insensitive volume.
        guard let lhs = try? FileManager.default.attributesOfItem(atPath: input.path),
              let rhs = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let lhsID = lhs[.systemFileNumber] as? NSNumber, let rhsID = rhs[.systemFileNumber] as? NSNumber,
              let lhsDevice = lhs[.systemNumber] as? NSNumber, let rhsDevice = rhs[.systemNumber] as? NSNumber else { return false }
        return lhsID == rhsID && lhsDevice == rhsDevice
    }
    guard !inputs.contains(where: sameFile) else {
        throw ToolError.usage("output must not replace an input: \(url.path)")
    }
    if FileManager.default.fileExists(atPath: url.path), !overwrite {
        throw ToolError.usage("output exists: \(url.path); choose a new path or use --overwrite for a file")
    }
}

func jsonData(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
}

func writeArtifact(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

func emit(_ result: [String: Any], options: TaskOptions, count: Int) throws {
    let data = try jsonData(result)
    if let output = options.values["--output"] {
        let url = pathURL(output)
        try writeArtifact(data, to: url)
        print(String(decoding: try jsonData(["output": url.path, "records": count, "bytes": data.count, "processing": "on-device", "api_cost_usd": 0]), as: UTF8.self))
    } else {
        print(String(decoding: data, as: UTF8.self))
    }
}

let textExtensions: Set<String> = ["txt", "md", "markdown", "log", "csv", "tsv", "json", "jsonl", "xml", "html", "htm", "yaml", "yml", "swift", "py", "js", "ts", "tsx", "jsx", "sh", "zsh"]
let documentExtensions = textExtensions.union(imageExts).union(["pdf"])

func inputFiles(_ input: String, extensions: Set<String>, excluding: String? = nil) throws -> [URL] {
    let root = pathURL(input)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
        throw ToolError.unreadable("no such file or folder: \(root.path)")
    }
    if !isDirectory.boolValue {
        guard extensions.contains(root.pathExtension.lowercased()) else { throw ToolError.usage("unsupported input type: \(root.lastPathComponent)") }
        return [root]
    }
    guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
        throw ToolError.unreadable("cannot read folder: \(root.path)")
    }
    let excluded = excluding.map { pathURL($0).resolvingSymlinksInPath().path }
    var files: [URL] = []
    for case let url as URL in iterator {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if properties.isSymbolicLink == true { iterator.skipDescendants(); continue }
        if let excluded, url.path == excluded || url.path.hasPrefix(excluded + "/") { iterator.skipDescendants(); continue }
        if properties.isRegularFile == true, extensions.contains(url.pathExtension.lowercased()) { files.append(url) }
    }
    guard !files.isEmpty else { throw ToolError.unreadable("no supported files in \(root.path)") }
    return files.sorted { $0.path < $1.path }
}

struct TextUnit {
    var source: String
    var page: Int?
    var line: Int
    var text: String
    var reference: [String: Any] { ["source": source, "page": page as Any? ?? NSNull(), "line_start": line] }
}

func textUnits(_ options: TaskOptions) throws -> [TextUnit] {
    if options.input == "-" {
        guard let text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) else { throw ToolError.unreadable("stdin must be UTF-8 text") }
        return [TextUnit(source: "stdin", line: 1, text: text)]
    }
    let maxPages = try options.integer("--max-pages", default: Int.max)
    return try inputFiles(options.input, extensions: documentExtensions, excluding: options.values["--output"]).flatMap { url -> [TextUnit] in
        if url.pathExtension.lowercased() == "pdf" || imageExts.contains(url.pathExtension.lowercased()) {
            let (pages, total) = try loadPages(url, range: options.values["--pages"], maxPages: maxPages, needImages: false, forceOCR: options.flags.contains("--force-ocr"))
            if pages.count < total { FileHandle.standardError.write(Data("processing \(pages.count)/\(total) pages of \(url.lastPathComponent)\n".utf8)) }
            return try pages.map { TextUnit(source: url.path, page: $0.number > 0 ? $0.number : nil, line: 1, text: try pageText($0)) }
        }
        return [TextUnit(source: url.path, line: 1, text: try String(contentsOf: url, encoding: .utf8))]
    }
}

func availableModel(tagging: Bool = false) throws -> SystemLanguageModel {
    let model = SystemLanguageModel(useCase: tagging ? .contentTagging : .general)
    guard case .available = model.availability else { throw ToolError.unreadable("Apple Intelligence unavailable: \(model.availability). Enable it in System Settings and allow model downloads to finish.") }
    return model
}

// Keep every character. Split at a newline where possible; large single lines are split
// by character. Query the actual tokenizer rather than guessing characters per token.
func modelChunks(_ unit: TextUnit, model: SystemLanguageModel, budget: Int) async throws -> [TextUnit] {
    guard budget >= 128 else { throw ToolError.usage("instructions/schema leave too little model context") }
    if try await model.tokenCount(for: unit.text) <= budget { return [unit] }
    guard unit.text.count > 1 else { throw ToolError.unreadable("cannot fit input in model context") }
    let midpoint = unit.text.index(unit.text.startIndex, offsetBy: unit.text.count / 2)
    let split = unit.text[..<midpoint].lastIndex(of: "\n").map { unit.text.index(after: $0) } ?? midpoint
    let first = String(unit.text[..<split]), second = String(unit.text[split...])
    let lhs = TextUnit(source: unit.source, page: unit.page, line: unit.line, text: first)
    let rhs = TextUnit(source: unit.source, page: unit.page, line: unit.line + first.filter { $0 == "\n" }.count, text: second)
    return try await modelChunks(lhs, model: model, budget: budget) + modelChunks(rhs, model: model, budget: budget)
}

func generationBudget(_ model: SystemLanguageModel, instructions: String, prompt: String, schema: GenerationSchema, responseTokens: Int = 1400) async throws -> Int {
    let overhead = try await model.tokenCount(for: instructions + prompt)
    let schemaTokens = try await model.tokenCount(for: schema)
    return min(2400, model.contextSize - overhead - schemaTokens - responseTokens - 200)
}

func withNewDirectory(_ output: String, body: (URL, URL) async throws -> [String: Any]) async throws {
    let destination = pathURL(output)
    guard !FileManager.default.fileExists(atPath: destination.path) else { throw ToolError.usage("output folder must be new: \(destination.path)") }
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    let staging = destination.deletingLastPathComponent().appendingPathComponent(".fm-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: staging) }
    var manifest = try await body(staging, destination)
    manifest["processing"] = "on-device"; manifest["api_cost_usd"] = 0
    try writeArtifact(try jsonData(manifest), to: staging.appendingPathComponent("manifest.json"))
    try FileManager.default.moveItem(at: staging, to: destination)
    let count = (manifest["files"] as? [Any])?.count ?? 0
    print(String(decoding: try jsonData(["output": destination.path, "manifest": destination.appendingPathComponent("manifest.json").path, "files": count, "processing": "on-device", "api_cost_usd": 0]), as: UTF8.self))
}

func runLocalTask(_ command: String, arguments: [String]) async throws {
    if arguments.contains("--help") { print(localUsage); return }
    switch command {
    case "extract": try await extractTask(arguments)
    case "classify": try await classifyTask(arguments)
    case "condense": try await condenseTask(arguments)
    case "table-to-csv": try await tableTask(arguments)
    case "local-search": try searchTask(arguments)
    case "transcribe-audio": try await transcribeTask(arguments)
    case "translate": try await translateTask(arguments)
    case "image-cutout": try await cutoutTask(arguments)
    default: throw ToolError.usage(localUsage)
    }
}
