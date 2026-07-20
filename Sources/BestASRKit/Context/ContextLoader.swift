import Foundation

/// Everything the context directory yielded, ready for rendering and
/// disclosure (design D4/D9).
/// One enrollment voice sample: `<label>.<ext>` under `voices/` (#26).
public struct EnrollmentVoice: Sendable, Equatable {
    public let label: String
    public let path: String
    public init(label: String, path: String) {
        self.label = label
        self.path = path
    }
}

public struct LoadedContext: Sendable, Equatable {
    public let directory: String
    public let document: ContextDocument?
    /// Terms merged from plain-text term lists, after context.json terms.
    public let termListTerms: [String]
    /// Unsupported files that were loudly ignored (spec: Loudly ignore
    /// unsupported document formats).
    public let ignoredFiles: [String]
    /// Enrollment voice samples in `voices/`, sorted by label (#26). Reserved
    /// + local-only: never parsed as terms, never in ignoredFiles, never leaves
    /// the machine (spec context-calibration).
    public var voices: [EnrollmentVoice] = []

    /// All terms: context.json terms first, then term-list terms.
    public var allTerms: [String] {
        (document?.terms ?? []) + termListTerms
    }

    public var names: [ContextDocument.Name] { document?.names ?? [] }
    public var phrases: [String] { document?.phrases ?? [] }

    /// A context with no values behaves exactly like no context at all
    /// (spec: Zero impact when context is absent).
    public var isEmpty: Bool {
        allTerms.isEmpty && names.isEmpty && phrases.isEmpty
    }

    public static let ingestGuidance =
        "run the context-ingest skill (bestasr plugin) to convert it into context.json"
}

/// Resolves and loads the context directory (spec context-calibration:
/// Resolve the context directory by three-layer precedence; design D1/D4).
public enum ContextLoader {
    public static let cwdDirectoryName = ".bestasr/context"

    static let termListExtensions: Set<String> = ["txt", "md"]

    /// Three-layer resolution, first hit wins, no merging:
    /// explicit flag > ./.bestasr/context/ > ~/.bestasr/context/.
    /// The legacy ./bestasr-context/ layer was removed (breaking); migrate by
    /// renaming the directory to ./.bestasr/context/.
    public static func resolveDirectory(
        flag: String?,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        if let flag {
            return URL(fileURLWithPath: (flag as NSString).expandingTildeInPath)
        }
        let cwdCandidate = cwd.appendingPathComponent(cwdDirectoryName, isDirectory: true)
        if directoryExists(cwdCandidate) { return cwdCandidate }
        let globalCandidate = home.appendingPathComponent(".bestasr/context", isDirectory: true)
        if directoryExists(globalCandidate) { return globalCandidate }
        return nil
    }

    /// Load the resolved directory's contents. Returns nil when nothing
    /// resolves; an explicitly flagged directory that does not exist is a
    /// usage error (the caller named it — silence would hide a typo).
    public static func load(
        flag: String?,
        cwd: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> LoadedContext? {
        guard let directory = resolveDirectory(flag: flag, cwd: cwd, home: home) else {
            return nil
        }
        if flag != nil, !directoryExists(directory) {
            throw BestASRError.usage("context directory not found: \(directory.path)")
        }
        return try load(directory: directory)
    }

    static func load(directory: URL) throws -> LoadedContext {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []

        var document: ContextDocument?
        var termListTerms: [String] = []
        var ignored: [String] = []
        var voices: [EnrollmentVoice] = []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let ext = entry.pathExtension.lowercased()
            let fileName = entry.lastPathComponent
            if fileName == "context.json" {
                let data = try Data(contentsOf: entry)
                document = try ContextDocument.load(data: data, fileName: entry.path)
            } else if termListExtensions.contains(ext) {
                termListTerms += parseTermList(try String(contentsOf: entry, encoding: .utf8))
            } else if ext.isEmpty && directoryExists(entry) {
                if fileName == "voices" { voices = collectVoices(in: entry) }
                continue  // other subdirectories are out of scope for v1
            } else {
                ignored.append(fileName)
            }
        }

        return LoadedContext(
            directory: directory.path,
            document: document,
            termListTerms: termListTerms,
            ignoredFiles: ignored,
            voices: voices
        )
    }

    static let voiceExtensions: Set<String> = ["wav", "m4a", "mp3"]

    /// Enrollment samples under `voices/` — reserved + local-only (#26). The
    /// filename stem is the verbatim speaker label; sorted by label for
    /// deterministic ordering.
    static func collectVoices(in dir: URL) -> [EnrollmentVoice] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { voiceExtensions.contains($0.pathExtension.lowercased()) }
            .map { EnrollmentVoice(label: $0.deletingPathExtension().lastPathComponent, path: $0.path) }
            .sorted { $0.label < $1.label }
    }

    /// One term per line; blank lines and `#` comment lines are skipped
    /// (spec: Merge plain-text term lists).
    static func parseTermList(_ content: String) -> [String] {
        content.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
