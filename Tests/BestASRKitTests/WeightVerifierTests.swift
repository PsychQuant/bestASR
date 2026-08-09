import Foundation
import Testing
@testable import BestASRKit

/// Weight-pinning contract (#52, spec weight-pinning): post-download digest
/// verification against the bundled manifest — TOFU for unpinned models,
/// fail-loud for any pinned mismatch.
struct WeightVerifierTests {
    private func makeCache(files: [String: String]) throws -> URL {
        let dir = try makeTempDir()
        for (rel, content) in files {
            let url = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.data(using: .utf8)!.write(to: url)
        }
        return dir
    }

    private func sha256(of text: String) -> String {
        WeightVerifier.digest(of: text.data(using: .utf8)!)
    }

    @Test func `Pinned model with intact weights passes`() throws {
        let cache = try makeCache(files: ["config.json": "cfg", "Encoder.mlmodelc/model.mil": "weights"])
        defer { try? FileManager.default.removeItem(at: cache) }
        let manifest = ["repo-a": [
            "config.json": sha256(of: "cfg"),
            "Encoder.mlmodelc/model.mil": sha256(of: "weights"),
        ]]
        let outcome = try WeightVerifier.verify(repo: "repo-a", cacheDir: cache, manifest: manifest)
        #expect(outcome == .verified(fileCount: 2))
    }

    @Test func `A drifted weight file fails loudly naming model and path`() throws {
        let cache = try makeCache(files: ["config.json": "TAMPERED"])
        defer { try? FileManager.default.removeItem(at: cache) }
        let manifest = ["repo-a": ["config.json": sha256(of: "cfg")]]
        do {
            _ = try WeightVerifier.verify(repo: "repo-a", cacheDir: cache, manifest: manifest)
            Issue.record("expected verify to throw")
        } catch let error as BestASRError {
            let message = String(describing: error)
            #expect(message.contains("repo-a"))
            #expect(message.contains("config.json"))
        }
    }

    @Test func `A missing pinned file is a mismatch`() throws {
        let cache = try makeCache(files: [:])
        defer { try? FileManager.default.removeItem(at: cache) }
        let manifest = ["repo-a": ["gone.bin": sha256(of: "x")]]
        #expect(throws: BestASRError.self) {
            _ = try WeightVerifier.verify(repo: "repo-a", cacheDir: cache, manifest: manifest)
        }
    }

    @Test func `Extra cache files not in the manifest do not fail`() throws {
        let cache = try makeCache(files: ["config.json": "cfg", "new-extra.json": "extra"])
        defer { try? FileManager.default.removeItem(at: cache) }
        let manifest = ["repo-a": ["config.json": sha256(of: "cfg")]]
        let outcome = try WeightVerifier.verify(repo: "repo-a", cacheDir: cache, manifest: manifest)
        #expect(outcome == .verified(fileCount: 1))
    }

    @Test func `An unpinned model is allowed through as the TOFU window`() throws {
        let cache = try makeCache(files: ["config.json": "cfg"])
        defer { try? FileManager.default.removeItem(at: cache) }
        let outcome = try WeightVerifier.verify(repo: "brand-new-repo", cacheDir: cache, manifest: [:])
        #expect(outcome == .unpinned)
    }

    @Test func `The bundled manifest resource loads and pins the live model set`() throws {
        let manifest = try WeightVerifier.bundledManifest()
        // The contract covers the repos the engine seams verify (#52); the
        // manifest MAY carry extra repos (the pin script scans the whole
        // cache) — those are inert without a seam referencing them.
        #expect(manifest.keys.contains("parakeet-tdt-0.6b-v3"))
        #expect(manifest.keys.contains("speaker-diarization"))
        #expect(manifest.values.allSatisfy { !$0.isEmpty })
    }
}

/// #163: `bundledManifest()` used to resolve the manifest through
/// `Bundle.module`, i.e. a `bestasr_BestASRKit.bundle` sitting next to the
/// executable. Neither install path ever put it there — `scripts/install.sh`
/// copies only the binaries, and the release ships only the binary — so on any
/// machine without a same-path source build the accessor hit `Swift.fatalError`
/// and the process died with SIGTRAP before it could report anything useful.
///
/// The manifest is a version-pinned static table, so it belongs *in* the
/// binary. These tests hold that line: one asserts it resolves without an
/// external bundle, the other that the embedded copy has not drifted from the
/// checked-in JSON that humans edit.
struct EmbeddedWeightsManifestTests {
    @Test func `Weights manifest resolves from the binary, not a side-car bundle`() throws {
        let embedded = try JSONDecoder().decode(
            [String: [String: String]].self,
            from: Data(WeightVerifier.embeddedManifestJSON.utf8))
        #expect(!embedded.isEmpty)
        #expect(try WeightVerifier.bundledManifest() == embedded)
    }

    @Test func `Embedded manifest has not drifted from the checked-in JSON`() throws {
        // #filePath anchors us to the source tree: Tests/BestASRKitTests/<this>
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // BestASRKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let onDiskURL = repoRoot.appendingPathComponent(
            "Sources/BestASRKit/Supply/weights-manifest.json")
        let onDisk = try JSONDecoder().decode(
            [String: [String: String]].self, from: Data(contentsOf: onDiskURL))
        #expect(
            try WeightVerifier.bundledManifest() == onDisk,
            "embedded manifest drifted — re-run scripts/embed-weights-manifest.sh")
    }
}
