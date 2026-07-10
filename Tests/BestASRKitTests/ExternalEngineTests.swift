import Foundation
import Testing
@testable import BestASRKit

/// External-engine protocol contract (#51, spec external-engine-protocol):
/// argv-spawned adapters speaking versioned JSON over stdout, contained to
/// one process per call, registered through ~/.bestasr/engines.json (tests
/// inject the registry directly — no home-directory access here). Fake
/// adapters are real executable scripts so the actual Process path is under
/// test, not a mock of it.
struct ExternalEngineTests {
    let options = TranscribeOptions(model: "qwen3-asr/4bit", quantization: "default", language: "en")

    private func makeAdapter(in dir: URL, script: String) throws -> String {
        let url = dir.appendingPathComponent("fake-adapter.sh")
        try ("#!/bin/bash\n" + script + "\n").data(using: .utf8)!.write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func engine(command: [String]) -> ExternalProcessEngine {
        ExternalProcessEngine(id: .mlxAudio, command: command)
    }

    @Test func `A conforming adapter transcribes through the seam`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(
            in: dir,
            script: #"echo '{"protocol":1,"text":"hello from outside","duration":2.0}'"#)
        let raw = try await engine(command: [adapter])
            .transcribeRaw(audioPath: "talk.wav", options: options)
        try #require(raw.segments.count == 1)
        #expect(raw.segments[0].text == "hello from outside")
        #expect(raw.segments[0].start == 0)
        #expect(raw.segments[0].end == 2.0)
        #expect(raw.segments[0].confidence == nil)
        #expect(raw.duration == 2.0)
    }

    @Test func `The adapter receives the protocol argv shape`() async throws {
        // The invocation contract is part of the protocol: subcommand +
        // --audio/--model flags (D1).
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let echoArgs = dir.appendingPathComponent("args.txt").path
        let adapter = try makeAdapter(
            in: dir,
            script: "echo \"$@\" > '\(echoArgs)'\n"
                + #"echo '{"protocol":1,"text":"x","duration":1.0}'"#)
        _ = try await engine(command: [adapter])
            .transcribeRaw(audioPath: "talk.wav", options: options)
        let args = try String(contentsOfFile: echoArgs, encoding: .utf8)
        #expect(args.contains("transcribe"))
        #expect(args.contains("--audio talk.wav"))
        #expect(args.contains("--model qwen3-asr/4bit"))
        #expect(args.contains("--language en"))
    }

    @Test func `Adapter failure is loud and attributed`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(
            in: dir, script: "echo 'model exploded' >&2\nexit 3")
        do {
            _ = try await engine(command: [adapter])
                .transcribeRaw(audioPath: "talk.wav", options: options)
            Issue.record("expected throw")
        } catch let error as TranscriptionError {
            #expect(error.backend == "mlx-audio")
            #expect(error.message.contains("model exploded"))
        }
    }

    @Test func `An unsupported protocol version is rejected`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(
            in: dir, script: #"echo '{"protocol":99,"text":"x","duration":1.0}'"#)
        do {
            _ = try await engine(command: [adapter])
                .transcribeRaw(audioPath: "talk.wav", options: options)
            Issue.record("expected throw")
        } catch let error as TranscriptionError {
            #expect(error.message.contains("99"))
        }
    }

    @Test func `Malformed stdout is a typed failure, not a crash`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(in: dir, script: "echo 'not json at all'")
        await #expect(throws: TranscriptionError.self) {
            _ = try await engine(command: [adapter])
                .transcribeRaw(audioPath: "talk.wav", options: options)
        }
    }

    @Test func `Timed segments flow through with the seam defenses`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(
            in: dir,
            script: #"echo '{"protocol":1,"text":"one two","duration":4.0,"segments":[{"start":0.0,"end":1.5,"text":"one"},{"start":2.5,"end":4.0,"text":" two"}]}'"#)
        let raw = try await engine(command: [adapter])
            .transcribeRaw(audioPath: "talk.wav", options: options)
        try #require(raw.segments.count == 2)
        #expect(raw.segments[0].text == "one")
        #expect(raw.segments[1].start == 2.5)
    }

    @Test func `A hung adapter is terminated at the timeout`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // 15 s: still 15x the 1 s test timeout, but a watchdog regression now
        // costs seconds of CI, not the hour-long hang of #91 (sleep 3600).
        let adapter = try makeAdapter(in: dir, script: "sleep 15")
        let hung = ExternalProcessEngine(
            id: .mlxAudio, command: [adapter], timeoutOverride: 1.0)
        do {
            _ = try await hung.transcribeRaw(audioPath: "talk.wav", options: options)
            Issue.record("expected timeout throw")
        } catch let error as TranscriptionError {
            #expect(error.message.lowercased().contains("timeout")
                || error.message.lowercased().contains("timed out"))
        }
    }

    // MARK: - registry (D6)

    @Test func `No config means no external backends`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let reg = ExternalEngineRegistry(configPath: dir.appendingPathComponent("none.json").path)
        #expect(reg.engines.isEmpty)
    }

    @Test func `A registered adapter enables its backend, unknown ids warn and drop`() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let adapter = try makeAdapter(in: dir, script: "exit 0")
        let cfg = dir.appendingPathComponent("engines.json")
        let json = """
            {"engines":[
              {"id":"mlx-audio","command":["\(adapter)"]},
              {"id":"not-a-backend","command":["/bin/true"]}
            ]}
            """
        try json.data(using: .utf8)!.write(to: cfg)
        let reg = ExternalEngineRegistry(configPath: cfg.path)
        #expect(reg.engines.count == 1)
        #expect(reg.engines[0].id == .mlxAudio)
    }

    @Test func `A missing executable leaves the backend unavailable`() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cfg = dir.appendingPathComponent("engines.json")
        try #"{"engines":[{"id":"mlx-audio","command":["/nonexistent/adapter"]}]}"#
            .data(using: .utf8)!.write(to: cfg)
        let reg = ExternalEngineRegistry(configPath: cfg.path)
        try #require(reg.engines.count == 1)
        let e = ExternalProcessEngine(id: reg.engines[0].id, command: reg.engines[0].command)
        #expect(await e.isAvailable() == false)
    }
}
