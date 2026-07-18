import Foundation
import Testing
@testable import BestASRKit

struct CorpusRowContributionTests {
    @Test func `New contribution fields round-trip through JSON`() throws {
        let row = CorpusRow(
            name: "cv-zh-0001", language: "zh",
            audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64),
            duration: 4.2, audioPath: "/tmp/a.wav", referencePath: "/tmp/a.txt",
            referenceProvenance: "human-proofread-from-whisper-large-v3",
            license: "CC0", attribution: "Common Voice clip 0001", contributor: "che")
        let back = try JSONDecoder().decode(CorpusRow.self, from: try JSONEncoder().encode(row))
        #expect(back == row)
        #expect(back.license == "CC0")
        #expect(back.referenceProvenance == "human-proofread-from-whisper-large-v3")
    }

    @Test func `Legacy corpus rows without contribution fields decode with nils`() throws {
        let legacy = """
        {"corpus_id":"aaaaaaaaaaaa","name":"old","language":"en",\
        "audio_sha256":"\(String(repeating: "a", count: 64))",\
        "reference_sha256":"\(String(repeating: "b", count: 64))",\
        "duration":3.0,"audio_path":"/x.wav","reference_path":"/x.txt"}
        """
        let row = try JSONDecoder().decode(CorpusRow.self, from: Data(legacy.utf8))
        #expect(row.license == nil)
        #expect(row.attribution == nil)
        #expect(row.contributor == nil)
        #expect(row.referenceProvenance == nil)
        #expect(row.name == "old")
    }
}
