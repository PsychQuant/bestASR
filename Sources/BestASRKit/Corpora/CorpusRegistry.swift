import Foundation

/// Corpus registration and listing (#14; spec corpora, design D8) — the v1
/// path for zh/ja user-supplied ground truth and the target the English
/// fetch script registers into.
public enum CorpusRegistry {
    /// `corpus add`: hash both files, probe duration, upsert by audio hash
    /// (re-adding moved audio updates paths — spec scenario).
    public static func add(
        audioPath: String, referencePath: String, language: String, name: String?,
        store: BenchmarkStore
    ) throws -> CorpusRow {
        let audioURL = URL(fileURLWithPath: (audioPath as NSString).expandingTildeInPath)
        let referenceURL = URL(fileURLWithPath: (referencePath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw BestASRError.usage("audio file not found: \(audioURL.path)")
        }
        guard FileManager.default.fileExists(atPath: referenceURL.path) else {
            throw BestASRError.usage("reference file not found: \(referenceURL.path)")
        }
        let normalizedLanguage = language.lowercased()
        guard normalizedLanguage.count == 2 else {
            throw BestASRError.usage("language must be a two-letter code (en/zh/ja/...)")
        }
        let audio = try AudioProber.probe(path: audioURL.path, requestedLanguage: nil)
        let row = CorpusRow(
            name: name ?? audioURL.deletingPathExtension().lastPathComponent,
            language: normalizedLanguage,
            audioSHA256: try fileSHA256(audioURL),
            referenceSHA256: try fileSHA256(referenceURL),
            duration: audio.duration ?? 0,
            audioPath: audioURL.path,
            referencePath: referenceURL.path)
        try store.upsert(corpus: row)
        return row
    }

    /// `corpus list`: registry as a table.
    public static func listTable(store: BenchmarkStore) throws -> String {
        let corpora = try store.load().corpora.sorted { ($0.language, $0.name) < ($1.language, $1.name) }
        guard !corpora.isEmpty else {
            return "No corpora registered. Add one with: bestasr corpus add <audio> <reference.srt> --language <code>"
        }
        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }
        var lines = [pad("LANG", 5) + pad("NAME", 22) + pad("DURATION", 10) + pad("ID", 14) + "AUDIO"]
        for corpus in corpora {
            lines.append(
                pad(corpus.language, 5) + pad(corpus.name, 22)
                    + pad(String(format: "%.1fs", corpus.duration), 10)
                    + pad(corpus.corpusId, 14) + corpus.audioPath)
        }
        return lines.joined(separator: "\n")
    }
}
