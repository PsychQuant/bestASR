import Foundation
import Testing
@testable import BestASRKit

// MARK: - 3.1 Worker protocol pure functions (spec mlx-audio-engine, D1)

struct MLXWorkerProtocolTests {
    @Test func `Request and response rows match the spec example`() throws {
        // Spec Example: request/response rows.
        let request = MLXWorkerProtocol.Request(id: 1, audio: "/tmp/clip.wav", language: "en")
        let encoded = try MLXWorkerProtocol.encode(request)
        #expect(encoded == #"{"audio":"/tmp/clip.wav","id":1,"language":"en"}"#)

        let line = #"{"id":1,"text":"hello world","segments":[{"start":0.0,"end":2.5,"text":"hello world"}],"language":"en","error":null}"#
        let response = try MLXWorkerProtocol.decodeResponse(line)
        #expect(response.text == "hello world")
        #expect(response.segments?.first?.end == 2.5)
        #expect(response.error == nil)
    }

    @Test func `Ready line decodes and non-ready lines do not`() {
        #expect(MLXWorkerProtocol.decodeReady(#"{"ready":true,"model":"x/y"}"#)?.ready == true)
        #expect(MLXWorkerProtocol.decodeReady("garbage") == nil)
    }

    @Test func `Error rows survive decoding without a payload`() throws {
        let response = try MLXWorkerProtocol.decodeResponse(
            #"{"id":3,"text":null,"segments":null,"language":null,"error":"boom"}"#)
        #expect(response.error == "boom")
    }

    @Test func `Segments absent maps to a single whole-text segment`() {
        // Spec scenario: segments absent.
        let response = MLXWorkerProtocol.Response(
            id: 1, text: "全文一段", segments: nil, language: "zh", error: nil)
        let raw = MLXWorkerProtocol.rawTranscription(from: response, duration: 30)
        #expect(raw.segments.count == 1)
        #expect(raw.segments[0].start == 0)
        #expect(raw.segments[0].end == 30)
        #expect(raw.segments[0].text == "全文一段")
    }
}

// MARK: - 3.3 Engine (transport spy; spec: availability / lifecycle / errors)

struct MLXAudioEngineTests {
    final class SpyTransport: MLXWorkerTransport, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requests: [MLXWorkerProtocol.Request] = []
        private(set) var terminated = false
        var responseText: String

        init(responseText: String = "hello world") {
            self.responseText = responseText
        }

        func send(_ request: MLXWorkerProtocol.Request) async throws -> MLXWorkerProtocol.Response {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return .init(
                id: request.id, text: responseText,
                segments: [.init(start: 0, end: 1, text: responseText)],
                language: request.language, error: nil)
        }

        func terminate() {
            lock.lock()
            defer { lock.unlock() }
            terminated = true
        }
    }

    /// A venv-shaped directory whose bin/python is a real executable — makes
    /// probeVenv's executable check pass paths we control in tests.
    func fakeVenv(importSucceeds: Bool) throws -> URL {
        let venv = try makeTempDir().appendingPathComponent("mlx-env")
        let bin = venv.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let python = bin.appendingPathComponent("python")
        let script = importSucceeds ? "#!/bin/sh\nexit 0\n" : "#!/bin/sh\nexit 1\n"
        try script.write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: python.path)
        return venv
    }

    @Test func `Missing venv reports unavailable and transcribe carries setup guidance`() async {
        let engine = MLXAudioEngine(
            venv: URL(fileURLWithPath: "/nonexistent/mlx-env"),
            makeTransport: { _, _, _ in SpyTransport() })
        #expect(await engine.isAvailable() == false)
        do {
            _ = try await engine.transcribe(
                audioPath: "x.wav",
                options: TranscribeOptions(model: "parakeet/0.6b", quantization: "default"))
            Issue.record("expected setup-guidance error")
        } catch let error as TranscriptionError {
            #expect(error.message.contains("uv venv"))
            #expect(error.message.contains("mlx-audio"))
        } catch { Issue.record("unexpected error type \(error)") }
    }

    @Test func `Verified grid row flows through the transport with language`() async throws {
        let spy = SpyTransport()
        let engine = MLXAudioEngine(
            venv: try fakeVenv(importSucceeds: true), makeTransport: { _, _, _ in spy })
        _ = try? await engine.transcribe(
            audioPath: "clip.wav",
            options: TranscribeOptions(model: "parakeet/0.6b", quantization: "default", language: "en"))
        // AudioProber fails on the fake path AFTER the worker round-trip —
        // the request capture is the assertion target.
        #expect(spy.requests.count == 1)
        #expect(spy.requests[0].audio == "clip.wav")
        #expect(spy.requests[0].language == "en")
    }

    @Test func `Unverified grid row errors with hub guidance, not a fabricated URL`() async throws {
        let engine = MLXAudioEngine(
            venv: try fakeVenv(importSucceeds: true), makeTransport: { _, _, _ in SpyTransport() })
        do {
            _ = try await engine.transcribe(
                audioPath: "x.wav",
                options: TranscribeOptions(model: "moonshine/base", quantization: "default"))
            Issue.record("expected unverified-row error")
        } catch let error as TranscriptionError {
            let message = error.message
            #expect(message.contains("huggingface.co/models?search="))
            #expect(!message.contains("resolve/main"))  // no fabricated download URL
        } catch { Issue.record("unexpected error type \(error)") }
    }

    @Test func `Worker error row surfaces as a typed transcription failure`() async throws {
        final class ErrorTransport: MLXWorkerTransport, @unchecked Sendable {
            func send(_ request: MLXWorkerProtocol.Request) async throws -> MLXWorkerProtocol.Response {
                .init(id: request.id, text: nil, segments: nil, language: nil, error: "OOM")
            }
            func terminate() {}
        }
        let engine = MLXAudioEngine(
            venv: try fakeVenv(importSucceeds: true), makeTransport: { _, _, _ in ErrorTransport() })
        do {
            _ = try await engine.transcribe(
                audioPath: "x.wav",
                options: TranscribeOptions(model: "whisper/large-v3-turbo", quantization: "default"))
            Issue.record("expected worker error")
        } catch let error as TranscriptionError {
            #expect(error.message == "OOM")
        } catch { Issue.record("unexpected error type \(error)") }
    }

    @Test func `Switching models terminates the previous worker`() async throws {
        // Spec scenario: switching models kills the old worker.
        let spyA = SpyTransport()
        let spyB = SpyTransport()
        let engine = MLXAudioEngine(
            venv: try fakeVenv(importSucceeds: true),
            makeTransport: { repo, _, _ in repo.contains("turbo") ? spyB : spyA })
        _ = try? await engine.transcribe(
            audioPath: "a.wav",
            options: TranscribeOptions(model: "parakeet/0.6b", quantization: "default"))
        _ = try? await engine.transcribe(
            audioPath: "b.wav",
            options: TranscribeOptions(model: "whisper/large-v3-turbo", quantization: "default"))
        #expect(spyA.terminated == true)
        #expect(spyB.terminated == false)
    }

    @Test func `Bad model address is a usage error`() async throws {
        let engine = MLXAudioEngine(
            venv: try fakeVenv(importSucceeds: true), makeTransport: { _, _, _ in SpyTransport() })
        do {
            _ = try await engine.transcribe(
                audioPath: "x.wav",
                options: TranscribeOptions(model: "tiny", quantization: "default"))
            Issue.record("expected address-format error")
        } catch let error as TranscriptionError {
            #expect(error.message.contains("family/size"))
        } catch { Issue.record("unexpected error type \(error)") }
    }
}


// MARK: - #15 supply-chain pin locks

struct RevisionPinTests {
    @Test func `Verified grid rows carry a pinned revision`() {
        for row in ModelGrid.rows(backend: ModelGrid.backendMLXAudio, priorityCeiling: nil)
        where row.verified {
            #expect(row.hfRevision != nil, "\(row.modelId) verified but unpinned")
            #expect(row.hfRevision?.count == 40)  // full commit sha
        }
    }

    @Test func `Worker arguments carry the pin and omit it when absent`() {
        let pinned = ProcessWorkerTransport.workerArguments(
            script: "/w.py", hfRepo: "a/b", revision: "abc123", family: "parakeet")
        #expect(pinned == ["/w.py", "--model", "a/b", "--revision", "abc123", "--model-type", "parakeet"])
        let unpinned = ProcessWorkerTransport.workerArguments(
            script: "/w.py", hfRepo: "a/b", revision: nil, family: "parakeet")
        #expect(!unpinned.contains("--revision"))
        #expect(!unpinned.contains("--model-type"))
    }

    @Test func `Factory receives the grid row's revision`() async throws {
        final class Capture: @unchecked Sendable {
            let lock = NSLock(); var revision: String??
            func set(_ r: String?) { lock.lock(); revision = r; lock.unlock() }
        }
        let captured = Capture()
        let engine = MLXAudioEngine(
            venv: try {
                let venv = try makeTempDir().appendingPathComponent("mlx-env")
                let bin = venv.appendingPathComponent("bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let py = bin.appendingPathComponent("python")
                try "#!/bin/sh\nexit 0\n".write(to: py, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: py.path)
                return venv
            }(),
            makeTransport: { _, revision, _ in
                captured.set(revision)
                return MLXAudioEngineTests.SpyTransport()
            })
        _ = try? await engine.transcribe(
            audioPath: "x.wav",
            options: TranscribeOptions(model: "parakeet/0.6b", quantization: "default"))
        #expect(captured.revision == "ed2b7e8c15f9aaa0b5772e2efb986255eaef7e15")
    }
}
