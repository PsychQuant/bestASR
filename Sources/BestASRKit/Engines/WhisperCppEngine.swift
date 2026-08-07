import Foundation

/// whisper.cpp backend — GGUF/GGML quantized path (design D3, secondary).
///
/// Integration decision (task 5.3): upstream whisper.cpp removed SwiftPM
/// support (no Package.swift on master), so per the design risk plan this
/// engine shells out to a `whisper-cli` binary (e.g. Homebrew's whisper-cpp
/// formula). Availability is honest: no binary on PATH → false.
public struct WhisperCppEngine: Engine {
    public let id: BackendID = .whisperCpp

    /// Where GGML model files live, e.g. ggml-small-q5_0.bin.
    public let modelDirectory: URL
    /// Override for tests; nil means "search PATH".
    let binaryPathOverride: String?
    /// Test seam, mirroring `ExternalProcessEngine.timeoutOverride`.
    ///
    /// Without it a regression test inherits the production budget, which for an
    /// unprobeable path is the 6-hour fallback — so a reintroduced deadlock
    /// would hang CI for six hours instead of failing (#165 verify B6). Tests
    /// pin a small budget so the failure is fast and legible.
    let timeoutOverride: TimeInterval?

    public init(
        modelDirectory: URL? = nil, binaryPathOverride: String? = nil,
        timeoutOverride: TimeInterval? = nil
    ) {
        self.modelDirectory =
            modelDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bestasr/models/whisper-cpp", isDirectory: true)
        self.binaryPathOverride = binaryPathOverride
        self.timeoutOverride = timeoutOverride
    }

    public func isAvailable() async -> Bool {
        Self.findBinary(override: binaryPathOverride) != nil
    }

    static func findBinary(override: String?) -> String? {
        if let override {
            return FileManager.default.isExecutableFile(atPath: override) ? override : nil
        }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for dir in searchPath.split(separator: ":") {
            let candidate = String(dir) + "/whisper-cli"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// ggml model file name for a (model, quantization) pair, matching the
    /// naming of the ggerganov/whisper.cpp model distribution.
    static func modelFileName(model: String, quantization: String) -> String {
        "ggml-\(model)-\(quantization).bin"
    }

    /// whisper-cli argument assembly — pure so tests can assert the prompt
    /// forwarding contract without launching a process (spec asr-engine).
    static func makeArguments(
        modelPath: String, audioPath: String, outputBase: String,
        language: String?, prompt: String?, deterministic: Bool = false
    ) -> [String] {
        var arguments = [
            "-m", modelPath,
            "-f", audioPath,
            "-oj",  // JSON output
            "-of", outputBase,
            "-np",  // no runtime prints
        ]
        if deterministic {
            // #34 regression gate: whisper-cli also retries failed segments at
            // increasing temperature; -nf keeps the decode greedy-reproducible.
            arguments += ["-nf"]
        }
        if let language {
            arguments += ["-l", language]
        }
        if let prompt {
            arguments += ["--prompt", prompt]
        }
        return arguments
    }

    /// Wall-clock budget for one whisper-cli run (#165).
    ///
    /// Derived from audio length rather than a fixed constant: a 5-minute cap
    /// would kill legitimate long transcriptions, and a cap generous enough for
    /// a 3-hour recording would let a 30-second clip wedge for hours. Measured
    /// reference on this class of hardware is ~44x realtime for large-v3-turbo,
    /// so 2x audio duration is ~88x slack — generous enough that only a genuine
    /// hang trips it. The floor covers cold model load on short clips; the
    /// unknown-duration fallback stays bounded rather than assuming the worst.
    static func timeout(forAudioAt path: String) -> TimeInterval {
        // `try?` flattens the throw and the optional `duration` into one
        // `Double?` — probe failure and "no duration" collapse to the same
        // bounded fallback, which is the behaviour we want either way.
        guard let seconds = try? AudioProber.probe(path: path).duration, seconds > 0 else {
            return 6 * 3600  // unreadable/unknown: bounded, not unbounded
        }
        return max(600, seconds * 2)
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        guard let binary = Self.findBinary(override: binaryPathOverride) else {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "whisper-cli not found on PATH; install with: brew install whisper-cpp"
            )
        }
        let modelFile = modelDirectory.appendingPathComponent(
            Self.modelFileName(model: options.model, quantization: options.quantization)
        )
        guard FileManager.default.fileExists(atPath: modelFile.path) else {
            throw TranscriptionError(
                backend: id.rawValue,
                message: """
                    model file missing: \(modelFile.path); download it with:
                    curl -L -o '\(modelFile.path)' \
                    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(Self.modelFileName(model: options.model, quantization: options.quantization))'
                    """
            )
        }

        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("bestasr-wcpp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputBase.appendingPathExtension("json")) }

        let arguments = Self.makeArguments(
            modelPath: modelFile.path,
            audioPath: audioPath,
            outputBase: outputBase.path,
            language: options.language,
            prompt: options.prompt,
            deterministic: options.deterministicDecode
        )

        // #165: whisper-cli chatters on stdout even under -np, and the result
        // lands in the -of JSON file rather than on stdout — which is why the
        // stream went unread here for so long. Unread is exactly the problem:
        // past 64 KB the child blocks in write(2) and we blocked forever in
        // waitUntilExit(). SubprocessRunner drains both pipes concurrently and
        // enforces a deadline, so neither failure mode is reachable.
        let (status, _, stderrText) = try await SubprocessRunner.run(
            executable: binary,
            arguments: arguments,
            timeout: timeoutOverride ?? Self.timeout(forAudioAt: audioPath),
            backend: id.rawValue
        )

        guard status == 0 else {
            let trimmed = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriptionError(
                backend: id.rawValue,
                message:
                    "whisper-cli exited \(status)"
                    + (trimmed.isEmpty ? "" : ": \(trimmed.suffix(300))")
            )
        }

        let jsonURL = outputBase.appendingPathExtension("json")
        guard let data = try? Data(contentsOf: jsonURL) else {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "whisper-cli produced no JSON output at \(jsonURL.path)"
            )
        }
        return try Self.parseOutput(data, backend: id.rawValue)
    }

    // MARK: - whisper-cli JSON parsing (pure, unit-tested)

    struct CLIOutput: Decodable {
        struct Result: Decodable { let language: String? }
        struct Entry: Decodable {
            struct Offsets: Decodable {
                let from: Double
                let to: Double
            }
            let offsets: Offsets
            let text: String
        }
        let result: Result?
        let transcription: [Entry]
    }

    static func parseOutput(_ data: Data, backend: String) throws -> RawTranscription {
        let decoded: CLIOutput
        do {
            decoded = try JSONDecoder().decode(CLIOutput.self, from: data)
        } catch {
            throw TranscriptionError(
                backend: backend,
                message: "cannot parse whisper-cli JSON output: \(error.localizedDescription)",
                underlying: error
            )
        }
        let segments = decoded.transcription.map { entry in
            RawTranscription.RawSegment(
                start: entry.offsets.from / 1000.0,  // whisper-cli offsets are milliseconds
                end: entry.offsets.to / 1000.0,
                text: entry.text
            )
        }
        return RawTranscription(
            segments: segments,
            language: decoded.result?.language,
            duration: nil
        )
    }
}
