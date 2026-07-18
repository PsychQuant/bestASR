import Foundation
import Testing
@testable import BestASRKit

struct CorpusManifestTests {
    private func sample() -> CorpusManifestRow {
        CorpusManifestRow(
            corpusId: "abc123abc123", name: "cv-zh-0001", language: "zh",
            audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64),
            duration: 4.2, license: "CC0", attribution: "Common Voice clip 0001",
            contributor: "che", referenceProvenance: "official",
            hfAudioPath: "audio/zh/cv-0001.wav", hfReferencePath: "reference/zh/cv-0001.txt")
    }

    @Test func `Manifest row round-trips through JSON`() throws {
        let row = sample()
        let back = try JSONDecoder().decode(CorpusManifestRow.self, from: try JSONEncoder().encode(row))
        #expect(back == row)
    }

    @Test func `parseJSONL reads rows and skips blank lines`() throws {
        let line = String(data: try JSONEncoder().encode(sample()), encoding: .utf8)!
        let jsonl = line + "\n\n" + line + "\n"   // 2 rows + a blank line
        let rows = try CorpusManifestRow.parseJSONL(jsonl)
        #expect(rows.count == 2)
        #expect(rows[0].language == "zh")
    }
}
