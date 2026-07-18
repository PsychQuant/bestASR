import Foundation

public struct ManifestValidationError: Equatable, Sendable {
    public let corpusId: String
    public let reason: String
    public init(corpusId: String, reason: String) {
        self.corpusId = corpusId
        self.reason = reason
    }
}

/// Mechanical manifest checks run by bench-repo CI and (defensively) by the
/// bench-contribute skill before opening a PR. Returns [] when the manifest
/// is clean.
public enum ManifestValidator {
    public static func validate(_ rows: [CorpusManifestRow]) -> [ManifestValidationError] {
        var errors: [ManifestValidationError] = []
        var seen = Set<String>()
        for row in rows {
            if CorpusLicense.parse(row.license) == nil {
                errors.append(.init(corpusId: row.corpusId,
                                    reason: "license '\(row.license)' not in allow-list"))
            }
            if row.attribution.trimmingCharacters(in: .whitespaces).isEmpty {
                errors.append(.init(corpusId: row.corpusId, reason: "attribution is empty"))
            }
            if !isHex64(row.audioSHA256) {
                errors.append(.init(corpusId: row.corpusId, reason: "audio_sha256 is not 64 hex chars"))
            }
            if !isHex64(row.referenceSHA256) {
                errors.append(.init(corpusId: row.corpusId, reason: "reference_sha256 is not 64 hex chars"))
            }
            if !seen.insert(row.corpusId).inserted {
                errors.append(.init(corpusId: row.corpusId, reason: "duplicate corpus_id"))
            }
        }
        return errors
    }

    static func isHex64(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { $0.isHexDigit }
    }
}
