import CryptoKit
import Foundation

/// Post-download weight verification against the bundled pinned manifest
/// (#52, spec weight-pinning). SwiftPM pins FluidAudio's *code* at an exact
/// version, but the CoreML weights come from HF `resolve/main` with no
/// integrity check — this verifier anchors trust at the maintainer's first
/// verified download (TOFU → pin, the corpora tsv-digest model, #34):
/// pinned mismatch fails loudly, unpinned models warn and proceed.
public enum WeightVerifier {
    public enum Outcome: Equatable, Sendable {
        /// Every manifest entry for the repo matched its cache digest.
        case verified(fileCount: Int)
        /// The repo has no manifest entries yet — the TOFU window.
        case unpinned
    }

    /// FluidAudio's model cache root (its documented download destination).
    public static var defaultCacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models")
    }

    /// Verify one model repo's cached files against the manifest. A manifest
    /// entry whose file is missing counts as a mismatch (spec: deletion is
    /// drift too); extra cache files never fail (pinning means "the files I
    /// depend on are unchanged", not "the directory is frozen").
    public static func verify(
        repo: String, cacheDir: URL, manifest: [String: [String: String]]
    ) throws -> Outcome {
        guard let pinned = manifest[repo] else { return .unpinned }
        for (relativePath, expected) in pinned.sorted(by: { $0.key < $1.key }) {
            let file = cacheDir.appendingPathComponent(relativePath)
            guard let data = try? Data(contentsOf: file) else {
                throw BestASRError.runtime(
                    "weight-pinning: '\(repo)' is pinned but '\(relativePath)' is missing "
                        + "from \(cacheDir.path) — refusing to load; re-download or re-pin "
                        + "via scripts/pin-weights.sh")
            }
            let actual = digest(of: data)
            guard actual == expected else {
                throw BestASRError.runtime(
                    "weight-pinning: '\(repo)' weight drift at '\(relativePath)' "
                        + "(expected \(expected.prefix(12))…, got \(actual.prefix(12))…) — "
                        + "refusing to load drifted weights; if this is an intentional "
                        + "upgrade, re-pin via scripts/pin-weights.sh")
            }
        }
        return .verified(fileCount: pinned.count)
    }

    /// Convenience for the engine seams: verify `repo` at the default cache
    /// root against the bundled manifest, printing the TOFU warning here so
    /// all three call sites stay one-liners.
    public static func verifyBundled(repo: String) throws {
        switch try verify(repo: repo, cacheDir: defaultCacheRoot.appendingPathComponent(repo),
                          manifest: try bundledManifest()) {
        case .verified:
            break
        case .unpinned:
            FileHandle.standardError.write(Data(
                ("warning: weight-pinning has no manifest entries for '\(repo)' (TOFU window) "
                    + "— run scripts/pin-weights.sh to pin it\n").utf8))
        }
    }

    /// The manifest bundled as a SwiftPM resource.
    public static func bundledManifest() throws -> [String: [String: String]] {
        guard let url = Bundle.module.url(forResource: "weights-manifest", withExtension: "json")
        else {
            throw BestASRError.runtime("weight-pinning: bundled weights-manifest.json not found")
        }
        return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
