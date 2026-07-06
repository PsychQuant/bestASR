import Foundation
import Testing
@testable import BestASRKit

/// #53 item 4: the end-to-end dispatch link — when the recommendation names a
/// non-whisper backend, CommandCore.transcribe really calls THAT engine.
/// (RouterCrossFamilyTests already locks "measured winner → rec.backend";
/// this locks "rec.backend → engine invoked" on the shared dispatch path,
/// so together the chain is covered without seeding a store.)
struct CrossFamilyDispatchTests {
    @Test func `A parakeet recommendation dispatches to the parakeet engine`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = try makeWavFile(in: dir)
        let core = CommandCore(
            engines: [
                MockEngine.fixed(.whisperKit, segments: [.init(start: 0, end: 1, text: "whisper text")]),
                MockEngine.fixed(.fluidParakeet, segments: [.init(start: 0, end: 1, text: "parakeet text")]),
            ],
            detect: { Fixtures.m5Max },
            store: BenchmarkStore(directory: dir.appendingPathComponent("store")),
            probe: .live()
        )
        let outcome = try await core.transcribe(
            audioPath: audio,
            selection: SelectionRequest(
                profileName: "medium", backendOverride: "fluid-parakeet", modelOverride: nil,
                requestedLanguage: "en", contextDir: nil),
            formatName: "txt",
            outputPath: dir.appendingPathComponent("out.txt").path)
        let text = try String(contentsOfFile: outcome.outputPath, encoding: .utf8)
        #expect(text.contains("parakeet text"))
        #expect(!text.contains("whisper text"))
    }
}
