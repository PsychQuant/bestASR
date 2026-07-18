import Testing
@testable import BestASRKit

struct ManifestValidatorTests {
    private func row(id: String = "abc123abc123", license: String = "CC0",
                     attribution: String = "src", sha: String = String(repeating: "a", count: 64))
        -> CorpusManifestRow {
        CorpusManifestRow(
            corpusId: id, name: "n", language: "zh", audioSHA256: sha,
            referenceSHA256: String(repeating: "b", count: 64), duration: 1.0,
            license: license, attribution: attribution, contributor: "che",
            referenceProvenance: "official", hfAudioPath: "a", hfReferencePath: "r")
    }

    @Test func `Valid manifest passes`() {
        #expect(ManifestValidator.validate([row(), row(id: "def456def456")]).isEmpty)
    }
    @Test func `Bad license is rejected`() {
        let errs = ManifestValidator.validate([row(license: "MIT")])
        #expect(errs.contains { $0.reason.contains("license") })
    }
    @Test func `Empty attribution is rejected`() {
        #expect(ManifestValidator.validate([row(attribution: "  ")]).contains { $0.reason.contains("attribution") })
    }
    @Test func `Non-64-hex sha is rejected`() {
        #expect(ManifestValidator.validate([row(sha: "xyz")]).contains { $0.reason.contains("sha256") })
    }
    @Test func `Duplicate corpus_id is rejected`() {
        let errs = ManifestValidator.validate([row(id: "dup000dup000"), row(id: "dup000dup000")])
        #expect(errs.contains { $0.reason.contains("duplicate") })
    }
}
