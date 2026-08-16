import Foundation
import Testing

@testable import BestASRKit

/// Read-time canonicalisation (#183, verify round 6 → maintainer chose option 1).
///
/// The store's keys are never rewritten. A measurement taken before the catalog
/// stated its quantization still says `default`; the catalog now says
/// `deferred:runtime`. Both name the same artifact, so both must resolve to one
/// identity — otherwise the same model competes with itself in the ranking pool,
/// which was round 4's CRITICAL.
struct CanonicalIdentityTests {

    @Test func `A placeholder quantization means whatever the catalog now states`() throws {
        let canon = try #require(
            ModelGrid.canonical(
                backend: "whisperkit", family: "whisper", size: "large-v3-turbo",
                quantization: ModelID.removedPlaceholder))
        #expect(canon.identity == ModelID(family: "whisper", size: "large-v3-turbo"))
        // WhisperKit fetches its own bundle, so the catalog says deferred.
        #expect(canon.quantization == .deferred(.runtime))

        // The OS-bundled row has no quantization axis at all.
        let apple = try #require(
            ModelGrid.canonical(
                backend: "apple-speech", family: "speechanalyzer", size: "system",
                quantization: ModelID.removedPlaceholder))
        #expect(apple.quantization == .notApplicable)
    }

    @Test func `A stored key and a fresh one collapse to the same identity`() throws {
        // This is the whole point. 140 measurements carry the first spelling;
        // every new one carries the second.
        let legacy = try #require(
            ModelGrid.canonical(
                backend: "whisperkit", family: "whisper", size: "large-v3-turbo",
                quantization: ModelID.removedPlaceholder))
        let fresh = try #require(
            ModelGrid.canonical(
                backend: "whisperkit", family: "whisper", size: "large-v3-turbo",
                quantization: Quantization.deferred(.runtime).serialised))
        #expect(legacy.identity == fresh.identity)
        #expect(legacy.quantization == fresh.quantization)
    }

    @Test func `A size the catalog has since renamed resolves to the new one`() throws {
        // `mlx-audio|parakeet|0.6b|default` — 15 measurements. Its pin is
        // mlx-community/parakeet-tdt-0.6b-v3, the same model the fluid row
        // hosts, so the two must become one identity without touching the file.
        let canon = try #require(
            ModelGrid.canonical(
                backend: "mlx-audio", family: "parakeet", size: "0.6b",
                quantization: ModelID.removedPlaceholder))
        #expect(canon.identity == ModelID(family: "parakeet", size: "0.6b-v3"))

        let fluid = try #require(
            ModelGrid.canonical(
                backend: "fluid-parakeet", family: "parakeet", size: "0.6b-v3",
                quantization: ModelID.removedPlaceholder))
        // #183's second EXPECTED, delivered: one model, two runtimes.
        #expect(canon.identity == fluid.identity)
    }

    @Test func `A legacy id whose family repeats its size still reads as whisper`() throws {
        let canon = try #require(
            ModelGrid.canonical(
                backend: "whisperkit", family: "base", size: "base",
                quantization: ModelID.removedPlaceholder))
        #expect(canon.identity == ModelID(family: "whisper", size: "base"))
    }

    @Test func `A real quantization is carried through untouched`() throws {
        let canon = try #require(
            ModelGrid.canonical(
                backend: "whisper.cpp", family: "whisper", size: "tiny",
                quantization: "q8_0"))
        #expect(canon.quantization == .named("q8_0"))
    }

    /// Non-vacuity: every key actually in the store must canonicalise.
    @Test func `Every stored key in the committed snapshot canonicalises`() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "docs/model-identity-audit.csv")
        var lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
        lines.removeFirst()
        let keys = lines.map { String($0.split(separator: ",")[0]) }
        #expect(keys.count == 37)
        for key in keys {
            let p = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let canon = ModelGrid.canonical(
                backend: p[0], family: p[1], size: p[2], quantization: p[3])
            #expect(canon != nil, "\(key) does not canonicalise")
        }
    }
}
