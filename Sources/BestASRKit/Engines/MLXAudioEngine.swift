import Foundation

/// mlx-audio backend (#14; spec mlx-audio-engine): MLX-native STT families via
/// a persistent JSON-lines Python worker per model. The worker loads the model
/// before printing its ready line, so warm-up absorbs the load and the timed
/// benchmark pass measures pure inference (the #7 discipline, third backend).
public struct MLXAudioEngine: Engine {
    public let id: BackendID = .mlxAudio

    /// Dedicated virtual environment (design D2) — never the system python.
    public static let defaultVenv = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".bestasr/mlx-env", isDirectory: true)

    public static let setupGuidance = """
        mlx-audio backend is not set up. Install it with:
          uv venv ~/.bestasr/mlx-env
          uv pip install --python ~/.bestasr/mlx-env/bin/python mlx-audio
        """

    let venv: URL
    /// Transport seam: tests inject a fake; production spawns mlx_worker.py.
    let makeTransport: @Sendable (_ hfRepo: String, _ revision: String?, _ family: String) async throws -> any MLXWorkerTransport

    let workers = CreateOnceStore<any MLXWorkerTransport>()

    public init(venv: URL? = nil) {
        let resolvedVenv = venv ?? Self.defaultVenv
        self.venv = resolvedVenv
        self.makeTransport = { hfRepo, revision, family in
            try await ProcessWorkerTransport(
                venv: resolvedVenv, hfRepo: hfRepo, revision: revision, family: family)
        }
    }

    init(
        venv: URL? = nil,
        makeTransport: @escaping @Sendable (String, String?, String) async throws -> any MLXWorkerTransport
    ) {
        self.venv = venv ?? Self.defaultVenv
        self.makeTransport = makeTransport
    }

    // MARK: - Availability (spec: Honest availability via dedicated venv)

    public func isAvailable() async -> Bool {
        Self.probeVenv(venv)
    }

    /// Memoized per venv path (design D2): availability queries and every
    /// transcribe would otherwise spawn a python subprocess — inside the
    /// benchmark's TIMED pass for mlx candidates only (verify #14 M-6/L-11).
    private static let probeCache = ProbeCache()

    final class ProbeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [String: Bool] = [:]
        func result(for key: String, compute: () -> Bool) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if let cached = results[key] { return cached }
            let value = compute()
            results[key] = value
            return value
        }
    }

    static func probeVenv(_ venv: URL) -> Bool {
        probeCache.result(for: venv.path) { probeVenvUncached(venv) }
    }

    static func probeVenvUncached(_ venv: URL) -> Bool {
        let python = venv.appendingPathComponent("bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else { return false }
        let process = Process()
        process.executableURL = python
        process.arguments = ["-c", "import mlx_audio"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // MARK: - Grid resolution

    /// `options.model` for this backend is `family/size`; the grid row supplies
    /// the HF repo. Unverified rows direct the user to the hub — never a
    /// guessed URL (spec model-grid: Unverified repo ids are marked).
    static func resolveRow(model: String, quantization: String) throws -> ModelRow {
        let parts = model.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            throw BestASRError.usage(
                "mlx-audio models are addressed as family/size (e.g. parakeet/0.6b); got '\(model)'"
            )
        }
        guard let row = ModelGrid.rows.first(where: {
            $0.backend == ModelGrid.backendMLXAudio && $0.family == parts[0]
                && $0.size == parts[1] && $0.quantization == quantization
        }) else {
            throw BestASRError.usage(
                "unknown mlx-audio grid row: \(model) (\(quantization)); run list-models for the catalog"
            )
        }
        guard row.verified, let repo = row.hfRepo else {
            throw BestASRError.runtime(
                "grid row \(row.modelId) has no verified HF repo yet — find the MLX build on "
                    + "https://huggingface.co/models?search=\(parts[0])%20mlx and file the repo id"
            )
        }
        return row
    }

    // MARK: - Transcription

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        guard Self.probeVenv(venv) else {
            throw TranscriptionError(backend: id.rawValue, message: Self.setupGuidance)
        }
        let row = try Self.resolveRow(model: options.model, quantization: options.quantization)
        guard let repo = row.hfRepo else {
            throw TranscriptionError(backend: id.rawValue, message: "unreachable: verified row without repo")
        }

        let worker: any MLXWorkerTransport
        do {
            // Keep-current eviction (spec: Worker lifecycle follows the
            // keep-current cache): evicted workers get terminated below.
            let evicted = await workers.retainOnlyReturningEvicted(repo)
            for old in evicted { old.terminate() }
            let factory = makeTransport
            let revision = row.hfRevision
            let family = row.family
            worker = try await workers.value(for: repo) { try await factory(repo, revision, family) }
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "failed to start mlx worker for \(repo): \(error.localizedDescription)",
                underlying: error
            )
        }

        // Context prompt: unsupported in v1 — honesty over silence (spec:
        // Output normalization and prompt honesty); disclosure happens in the
        // explain path via promptUnsupported.
        let request = MLXWorkerProtocol.Request(
            id: nextRequestId(), audio: audioPath, language: options.language)
        let response: MLXWorkerProtocol.Response
        do {
            response = try await worker.send(request)
        } catch {
            // A worker that died after becoming ready must not stay cached —
            // evict so the next call restarts it (verify #14 L-13).
            await workers.remove(repo)
            worker.terminate()
            throw TranscriptionError(
                backend: id.rawValue,
                message: "mlx worker request failed: \(error.localizedDescription)",
                underlying: error
            )
        }
        if let workerError = response.error {
            throw TranscriptionError(backend: id.rawValue, message: workerError)
        }
        // Duration is only needed for the whole-text fallback; segments carry
        // their own bounds — keeps the probe out of the timed pass (M-6).
        let duration: Double?
        if let segments = response.segments, let last = segments.last {
            duration = last.end
        } else {
            duration = (try? AudioProber.probe(path: audioPath, requestedLanguage: nil))?.duration ?? nil
        }
        return MLXWorkerProtocol.rawTranscription(from: response, duration: duration)
    }

    /// This backend cannot bias decoding with a context prompt in v1.
    public static let promptUnsupportedNote =
        "context prompt not supported by the mlx-audio backend (v1) — proofread via srt-proofread instead"
}

private let requestCounter = OSAllocatedUnfairLockCounter()

func nextRequestId() -> Int { requestCounter.next() }

final class OSAllocatedUnfairLockCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

// MARK: - Transport seam (design D2/D9)

public protocol MLXWorkerTransport {
    func send(_ request: MLXWorkerProtocol.Request) async throws -> MLXWorkerProtocol.Response
    func terminate()
}

/// Production transport: spawns mlx_worker.py with the venv python, waits for
/// the ready line, then exchanges JSON lines.
final class ProcessWorkerTransport: MLXWorkerTransport, @unchecked Sendable {
    private let process: Process
    private let stdin: FileHandle
    private let stdout: FileHandle
    private let lock = NSLock()
    private var buffer = Data()

    /// Pure argument assembly — pin passthrough is unit-tested (#15).
    static func workerArguments(
        script: String, hfRepo: String, revision: String?, family: String
    ) -> [String] {
        var arguments = [script, "--model", hfRepo]
        if let revision {
            // Pinned snapshot dirs are bare shas — the worker needs the
            // family for mlx_audio's type dispatch (#15).
            arguments += ["--revision", revision, "--model-type", family]
        }
        return arguments
    }

    init(venv: URL, hfRepo: String, revision: String?, family: String) async throws {
        guard let script = Bundle.module.url(forResource: "mlx_worker", withExtension: "py")
        else {
            throw TranscriptionError(
                backend: BackendID.mlxAudio.rawValue,
                message: "mlx_worker.py missing from bundle resources")
        }
        let process = Process()
        process.executableURL = venv.appendingPathComponent("bin/python")
        process.arguments = Self.workerArguments(
            script: script.path, hfRepo: hfRepo, revision: revision, family: family)
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = Pipe()
        try process.run()
        self.process = process
        self.stdin = inPipe.fileHandleForWriting
        self.stdout = outPipe.fileHandleForReading

        // Ready line = model loaded (warm-up boundary). No arbitrary timeout:
        // large first-time downloads are legitimate; the user can interrupt.
        guard let line = readLine(), MLXWorkerProtocol.decodeReady(line)?.ready == true else {
            process.terminate()
            throw TranscriptionError(
                backend: BackendID.mlxAudio.rawValue,
                message: "mlx worker for \(hfRepo) did not become ready (model load failed?)")
        }
    }

    func send(_ request: MLXWorkerProtocol.Request) async throws -> MLXWorkerProtocol.Response {
        lock.lock()
        defer { lock.unlock() }
        let payload = try MLXWorkerProtocol.encode(request) + "\n"
        try stdin.write(contentsOf: Data(payload.utf8))
        // Correlate on id and tolerate stray stdout lines (ML libraries print;
        // verify #14 M-7): skip undecodable/mismatched lines up to a cap.
        var skipped = 0
        while skipped < 64 {
            guard let line = readLineLocked() else {
                throw TranscriptionError(
                    backend: BackendID.mlxAudio.rawValue, message: "mlx worker closed its pipe")
            }
            if let response = try? MLXWorkerProtocol.decodeResponse(line),
                response.id == request.id
            {
                return response
            }
            skipped += 1
        }
        throw TranscriptionError(
            backend: BackendID.mlxAudio.rawValue,
            message: "mlx worker produced no matching response for request \(request.id)")
    }

    func terminate() {
        try? stdin.close()
        process.terminate()
    }

    private func readLine() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return readLineLocked()
    }

    private func readLineLocked() -> String? {
        while true {
            if let index = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer[..<index]
                buffer.removeSubrange(...index)
                if let line = String(data: Data(lineData), encoding: .utf8),
                    !line.trimmingCharacters(in: .whitespaces).isEmpty
                {
                    return line
                }
                continue
            }
            let chunk = stdout.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
