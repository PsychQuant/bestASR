import Foundation
import Testing

@testable import BestASRKit

/// Phase 1 Plan 2 cores: submission packaging/dedupe, pull planning +
/// integrity, and the contribute licensing gate.
struct SharingTests {
    private let date = Date(timeIntervalSince1970: 1_752_800_000)

    private func measurement(model: String = "whisperkit|whisper|large-v3|default")
        -> MeasurementRow {
        MeasurementRow(
            modelId: model, corpusId: "abc123abc123",
            machineId: MachineRow.id(chip: "Apple M5 Max", unifiedMemoryGB: 128),
            measuredAt: date, metricKind: .cer, errorRate: 0.12, rtf: 0.14,
            peakMemoryGB: 3.1, warmupSeconds: 8.0, appVersion: "0.14.0",
            macosVersion: "26.0")
    }

    private var machine: MachineRow { MachineRow(chip: "Apple M5 Max", unifiedMemoryGB: 128) }

    @Test func `Packaging denormalizes machine facts and stamps the contributor`() {
        let rows = SubmissionPackager.package(
            local: [measurement()], machines: [machine],
            canonicalCorpusIds: ["abc123abc123"], publishedKeys: [], contributor: "che")
        #expect(rows.count == 1)
        #expect(rows[0].chip == "Apple M5 Max")
        #expect(rows[0].unifiedMemoryGB == 128)
        #expect(rows[0].contributor == "che")
    }

    @Test func `Measurements on local-only corpora never travel`() {
        let rows = SubmissionPackager.package(
            local: [measurement()], machines: [machine],
            canonicalCorpusIds: ["different0000"], publishedKeys: [], contributor: "che")
        #expect(rows.isEmpty)
    }

    @Test func `Rows the repo already has are dropped by dedupe key`() {
        let first = SubmissionPackager.package(
            local: [measurement()], machines: [machine],
            canonicalCorpusIds: ["abc123abc123"], publishedKeys: [], contributor: "che")
        let again = SubmissionPackager.package(
            local: [measurement()], machines: [machine], canonicalCorpusIds: ["abc123abc123"],
            publishedKeys: [first[0].dedupeKey], contributor: "che")
        #expect(again.isEmpty)
    }

    @Test func `JSONL round-trips through publishedKeys`() throws {
        let rows = SubmissionPackager.package(
            local: [measurement(), measurement(model: "whisperkit|whisper|small|default")],
            machines: [machine], canonicalCorpusIds: ["abc123abc123"],
            publishedKeys: [], contributor: "che")
        let jsonl = try SubmissionPackager.encodeJSONL(rows)
        let keys = SubmissionPackager.publishedKeys(fromJSONL: jsonl)
        #expect(keys == Set(rows.map(\.dedupeKey)))
    }

    @Test func `Submission filename is UTC-stamped and machine-scoped`() {
        let name = SubmissionPackager.filename(
            date: date, contributor: "che", machineId: String(repeating: "a", count: 40))
        #expect(name.hasSuffix("-che-aaaaaaaaaaaa.jsonl"))
        #expect(name.first?.isNumber == true)
        #expect(name.contains("T"))
    }

    @Test func `Pull plan builds HF resolve URLs and mirrored destinations`() {
        let row = CorpusManifestRow(
            corpusId: "abc123abc123", name: "cv-zh-0001", language: "zh",
            audioSHA256: String(repeating: "a", count: 64),
            referenceSHA256: String(repeating: "b", count: 64), duration: 4.2,
            license: "CC-BY", attribution: "FLEURS", contributor: "che",
            referenceProvenance: "official",
            hfAudioPath: "audio/zh/cv-0001.wav", hfReferencePath: "reference/zh/cv-0001.txt")
        let items = CorpusPuller.plan(
            manifest: [row], hfDataset: "PsychQuant/bestasr-corpus",
            destinationRoot: URL(fileURLWithPath: "/tmp/corpus"))
        #expect(items.count == 1)
        #expect(items[0].audioURL.absoluteString
            == "https://huggingface.co/datasets/PsychQuant/bestasr-corpus/resolve/main/audio/zh/cv-0001.wav")
        #expect(items[0].referenceDestination.path == "/tmp/corpus/reference/zh/cv-0001.txt")
    }

    @Test func `Pull verify rejects a SHA mismatch`() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pull-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let audio = dir.appendingPathComponent("a.wav")
        let reference = dir.appendingPathComponent("r.txt")
        try Data("audio-bytes".utf8).write(to: audio)
        try Data("ref-bytes".utf8).write(to: reference)
        let row = CorpusManifestRow(
            corpusId: "abc123abc123", name: "x", language: "zh",
            audioSHA256: try fileSHA256(audio),
            referenceSHA256: String(repeating: "0", count: 64),  // wrong on purpose
            duration: 1, license: "CC0", attribution: "src", contributor: "che",
            referenceProvenance: "official", hfAudioPath: "a.wav", hfReferencePath: "r.txt")
        let item = CorpusPuller.PullItem(
            row: row, audioURL: audio, referenceURL: reference,
            audioDestination: audio, referenceDestination: reference)
        #expect(throws: (any Error).self) { try CorpusPuller.verify(item: item) }
    }

    @Test func `Contribute gate demands allow-listed license, attribution, and consent`() throws {
        #expect(try ContributionGate.validate(
            license: "CC-BY", attribution: "FLEURS", consentAsserted: true) == .ccBy)
        #expect(throws: (any Error).self) {
            try ContributionGate.validate(license: "MIT", attribution: "x", consentAsserted: true)
        }
        #expect(throws: (any Error).self) {
            try ContributionGate.validate(license: "CC0", attribution: "  ", consentAsserted: true)
        }
        #expect(throws: (any Error).self) {
            try ContributionGate.validate(license: "CC0", attribution: "x", consentAsserted: false)
        }
    }
}
