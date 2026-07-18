import ArgumentParser
import BestASRKit
import Foundation

/// Community-benchmark sharing commands (Phase 1 Plan 2). Cores live in
/// BestASRKit `Contribution/Sharing.swift`; this file is the thin shell:
/// network fetches, `gh`/`hf` subprocess mechanics, and printing.

/// Minimal subprocess runner for the sharing commands (`gh`, `hf`, `git`).
enum ToolRunner {
    @discardableResult
    static func output(_ tool: String, _ args: [String], cwd: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [tool] + args
        if let cwd { process.currentDirectoryURL = cwd }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw BestASRError.runtime("could not launch '\(tool)': \(error.localizedDescription)")
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BestASRError.runtime(
                "\(tool) \(args.prefix(2).joined(separator: " ")) failed"
                    + (detail.isEmpty ? "" : ": \(detail)"))
        }
        return String(decoding: outData, as: UTF8.self)
    }
}

private func fetchText(_ url: URL) async throws -> String {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw BestASRError.runtime("GET \(url.absoluteString) returned HTTP \(code)")
    }
    return String(decoding: data, as: UTF8.self)
}

private func download(_ url: URL, to destination: URL) async throws {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw BestASRError.runtime("GET \(url.absoluteString) returned HTTP \(code)")
    }
    try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: destination)
}

// MARK: - bench submit

struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Share measurements with the community benchmark",
        subcommands: [Submit.self]
    )

    struct Submit: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Package unsubmitted local measurements and open a bench-repo PR")

        @Option(help: "Bench repo (owner/name)") var repo: String = BenchTargets.benchRepo
        @Flag(name: .customLong("dry-run"), help: "Show what would be submitted, change nothing")
        var dryRun = false

        func run() async throws {
            try await runMapped {
                let tables = try BenchmarkStore().load()
                guard !tables.measurements.isEmpty else {
                    print("No local measurements. Run: bestasr benchmark <audio> --reference <truth.srt>")
                    return
                }
                let contributor = try ToolRunner.output("gh", ["api", "user", "--jq", ".login"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // Canonical corpus ids — only measurements against the shared
                // corpus are comparable (local/private corpora stay local).
                let manifestURL = URL(
                    string: "https://raw.githubusercontent.com/\(repo)/main/corpus/manifest.jsonl")!
                let canonical = Set(
                    try CorpusManifestRow.parseJSONL(try await fetchText(manifestURL))
                        .map(\.corpusId))

                // Published rows → dedupe keys. A missing/empty measurements
                // dir is a young repo, not an error.
                var published = Set<String>()
                if let listing = try? ToolRunner.output(
                    "gh",
                    ["api", "repos/\(repo)/contents/measurements",
                     "--jq", ".[] | select(.name|endswith(\".jsonl\")) | .download_url"]) {
                    for line in listing.split(separator: "\n") {
                        guard let url = URL(string: String(line)) else { continue }
                        published.formUnion(
                            SubmissionPackager.publishedKeys(fromJSONL: try await fetchText(url)))
                    }
                }

                let rows = SubmissionPackager.package(
                    local: tables.measurements, machines: tables.machines,
                    canonicalCorpusIds: canonical,
                    publishedKeys: published, contributor: contributor)
                let localOnly = tables.measurements.count(where: { !canonical.contains($0.corpusId) })
                if localOnly > 0 {
                    print("(\(localOnly) measurement(s) on local-only corpora stay local — "
                        + "run 'bestasr corpus pull' + benchmark the canonical corpus to share)")
                }
                guard !rows.isEmpty else {
                    print("Nothing new to submit against the canonical corpus.")
                    return
                }
                let filename = SubmissionPackager.filename(
                    date: Date(), contributor: contributor, machineId: rows[0].machineId)
                let jsonl = try SubmissionPackager.encodeJSONL(rows)
                if dryRun {
                    print("Would submit \(rows.count) new row(s) as measurements/\(filename)")
                    return
                }

                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bestasr-submit-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: work) }
                try ToolRunner.output(
                    "gh", ["repo", "clone", repo, work.path, "--", "--depth", "1"])
                let branch = "submit/\(filename.replacingOccurrences(of: ".jsonl", with: ""))"
                try ToolRunner.output("git", ["checkout", "-b", branch], cwd: work)
                try jsonl.write(
                    to: work.appendingPathComponent("measurements/\(filename)"),
                    atomically: true, encoding: .utf8)
                try ToolRunner.output("git", ["add", "measurements/\(filename)"], cwd: work)
                try ToolRunner.output(
                    "git",
                    ["commit", "-m", "data: \(rows.count) measurement(s) from \(contributor)"],
                    cwd: work)
                try ToolRunner.output("git", ["push", "origin", branch], cwd: work)
                let prURL = try ToolRunner.output(
                    "gh",
                    ["pr", "create", "-R", repo, "--head", branch,
                     "--title", "data: \(rows.count) measurement(s) from \(contributor)",
                     "--body",
                     "Automated `bestasr bench submit` — \(rows.count) new row(s) in "
                         + "`measurements/\(filename)`. CI validates schema/ranges/dedupe."],
                    cwd: work)
                print("Opened PR: \(prURL.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }
}

// MARK: - corpus pull / contribute

extension Corpus {
    struct Pull: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Fetch the canonical community corpus and register it locally")

        @Option(help: "Bench repo (owner/name)") var repo: String = BenchTargets.benchRepo
        @Option(name: .customLong("hf-repo"), help: "HF dataset (namespace/name)")
        var hfRepo: String = BenchTargets.hfDataset

        func run() async throws {
            try await runMapped {
                let manifestURL = URL(
                    string: "https://raw.githubusercontent.com/\(repo)/main/corpus/manifest.jsonl")!
                let manifest = try CorpusManifestRow.parseJSONL(try await fetchText(manifestURL))
                guard !manifest.isEmpty else {
                    print("The canonical corpus manifest is empty — nothing to pull.")
                    return
                }
                let root = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".bestasr/corpus")
                let store = BenchmarkStore()
                var pulled = 0
                var refreshed = 0
                for item in CorpusPuller.plan(
                    manifest: manifest, hfDataset: hfRepo, destinationRoot: root) {
                    let alreadyGood =
                        FileManager.default.fileExists(atPath: item.audioDestination.path)
                        && FileManager.default.fileExists(atPath: item.referenceDestination.path)
                        && (try? CorpusPuller.verify(item: item)) != nil
                    if !alreadyGood {
                        try await download(item.audioURL, to: item.audioDestination)
                        try await download(item.referenceURL, to: item.referenceDestination)
                        try CorpusPuller.verify(item: item)
                        pulled += 1
                    } else {
                        refreshed += 1
                    }
                    _ = try CorpusRegistry.add(
                        audioPath: item.audioDestination.path,
                        referencePath: item.referenceDestination.path,
                        language: item.row.language, name: item.row.name, store: store)
                }
                print("Corpus pull: \(pulled) downloaded, \(refreshed) already current, "
                    + "\(manifest.count) registered. Next: bestasr benchmark")
            }
        }
    }

    struct Contribute: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Publish an audio + reference pair to the shared corpus (license-gated)")

        @Argument(help: "Audio file path") var audio: String
        @Argument(help: "Reference transcript path") var reference: String
        @Option(help: "Two-letter language code (en/zh/ja/...)") var language: String
        @Option(help: "License: CC0 | CC-BY | CC-BY-SA | public-domain | own-consented")
        var license: String
        @Option(help: "Source attribution (where this audio comes from)") var attribution: String
        @Option(help: "Display name (default: audio file name)") var name: String?
        @Option(help: "Reference provenance: official | manual | human-proofread-from-<model>")
        var provenance: String = "manual"
        @Flag(help: "Assert you may publish this audio and identifiable speakers consented")
        var consent = false
        @Option(help: "Bench repo (owner/name)") var repo: String = BenchTargets.benchRepo
        @Option(name: .customLong("hf-repo"), help: "HF dataset (namespace/name)")
        var hfRepo: String = BenchTargets.hfDataset

        func run() async throws {
            try await runMapped {
                let gateLicense = try ContributionGate.validate(
                    license: license, attribution: attribution, consentAsserted: consent)
                // Register locally first — hashes, duration, upsert.
                let row = try CorpusRegistry.add(
                    audioPath: audio, referencePath: reference, language: language,
                    name: name, store: BenchmarkStore())
                let contributor = try ToolRunner.output("gh", ["api", "user", "--jq", ".login"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let audioExt = URL(fileURLWithPath: audio).pathExtension
                let refExt = URL(fileURLWithPath: reference).pathExtension
                let hfAudioPath = "audio/\(row.language)/\(row.name).\(audioExt)"
                let hfReferencePath = "reference/\(row.language)/\(row.name).\(refExt)"

                // Upload to the HF dataset (requires `hf auth login`).
                for (local, remote) in [(audio, hfAudioPath), (reference, hfReferencePath)] {
                    try ToolRunner.output(
                        "hf",
                        ["upload", hfRepo, local, remote, "--repo-type", "dataset",
                         "--commit-message", "data: contribute \(row.name) (\(row.language))"])
                }

                let manifestRow = CorpusManifestRow(
                    corpusId: row.corpusId, name: row.name, language: row.language,
                    audioSHA256: row.audioSHA256, referenceSHA256: row.referenceSHA256,
                    duration: row.duration, license: gateLicense.rawValue,
                    attribution: attribution, contributor: contributor,
                    referenceProvenance: provenance,
                    hfAudioPath: hfAudioPath, hfReferencePath: hfReferencePath)

                // Manifest PR — validated in-process before anything is pushed.
                let work = FileManager.default.temporaryDirectory
                    .appendingPathComponent("bestasr-contribute-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: work) }
                try ToolRunner.output(
                    "gh", ["repo", "clone", repo, work.path, "--", "--depth", "1"])
                let manifestPath = work.appendingPathComponent("corpus/manifest.jsonl")
                let existing = try CorpusManifestRow.parseJSONL(
                    (try? String(contentsOf: manifestPath, encoding: .utf8)) ?? "")
                let combined = existing + [manifestRow]
                let issues = ManifestValidator.validate(combined)
                guard issues.isEmpty else {
                    throw BestASRError.usage(
                        "manifest validation failed: "
                            + issues.map { "\($0.corpusId): \($0.reason)" }
                                .joined(separator: "; "))
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let lines = try combined.map {
                    String(decoding: try encoder.encode($0), as: UTF8.self)
                }
                try (lines.joined(separator: "\n") + "\n").write(
                    to: manifestPath, atomically: true, encoding: .utf8)
                let branch = "corpus/\(row.corpusId)"
                try ToolRunner.output("git", ["checkout", "-b", branch], cwd: work)
                try ToolRunner.output("git", ["add", "corpus/manifest.jsonl"], cwd: work)
                try ToolRunner.output(
                    "git",
                    ["commit", "-m", "data: contribute corpus \(row.name) (\(row.language))"],
                    cwd: work)
                try ToolRunner.output("git", ["push", "origin", branch], cwd: work)
                let prURL = try ToolRunner.output(
                    "gh",
                    ["pr", "create", "-R", repo, "--head", branch,
                     "--title", "data: contribute corpus \(row.name) (\(row.language))",
                     "--body",
                     "License: \(gateLicense.rawValue) · attribution: \(attribution) · "
                         + "provenance: \(provenance). Audio uploaded to `\(hfRepo)`. "
                         + "Human review: license check + reference quality."],
                    cwd: work)
                print("Opened PR: \(prURL.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
    }
}
