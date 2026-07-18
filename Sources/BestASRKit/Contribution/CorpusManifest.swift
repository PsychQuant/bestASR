import Foundation

/// One entry of the shared corpus manifest (lives in bench repo
/// `corpus/manifest.jsonl`). The public, machine-independent projection of a
/// CorpusRow: identity hashes + community metadata + pointers into the HF
/// dataset. Machine-local audio/reference paths are deliberately NOT here.
public struct CorpusManifestRow: Codable, Sendable, Equatable {
    public let corpusId: String
    public let name: String
    public let language: String
    public let audioSHA256: String
    public let referenceSHA256: String
    public let duration: Double
    public let license: String
    public let attribution: String
    public let contributor: String
    public let referenceProvenance: String
    public let hfAudioPath: String
    public let hfReferencePath: String

    enum CodingKeys: String, CodingKey {
        case corpusId = "corpus_id"
        case name, language
        case audioSHA256 = "audio_sha256"
        case referenceSHA256 = "reference_sha256"
        case duration, license, attribution, contributor
        case referenceProvenance = "reference_provenance"
        case hfAudioPath = "hf_audio_path"
        case hfReferencePath = "hf_reference_path"
    }

    public init(
        corpusId: String, name: String, language: String,
        audioSHA256: String, referenceSHA256: String, duration: Double,
        license: String, attribution: String, contributor: String,
        referenceProvenance: String, hfAudioPath: String, hfReferencePath: String
    ) {
        self.corpusId = corpusId
        self.name = name
        self.language = language
        self.audioSHA256 = audioSHA256
        self.referenceSHA256 = referenceSHA256
        self.duration = duration
        self.license = license
        self.attribution = attribution
        self.contributor = contributor
        self.referenceProvenance = referenceProvenance
        self.hfAudioPath = hfAudioPath
        self.hfReferencePath = hfReferencePath
    }

    /// Parse a JSONL manifest (one row per line; blank lines skipped).
    public static func parseJSONL(_ text: String) throws -> [CorpusManifestRow] {
        try text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            return try JSONDecoder().decode(CorpusManifestRow.self, from: Data(trimmed.utf8))
        }
    }
}
