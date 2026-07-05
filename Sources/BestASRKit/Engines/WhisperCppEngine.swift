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

    public init(modelDirectory: URL? = nil, binaryPathOverride: String? = nil) {
        self.modelDirectory =
            modelDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bestasr/models/whisper-cpp", isDirectory: true)
        self.binaryPathOverride = binaryPathOverride
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "failed to launch whisper-cli: \(error.localizedDescription)",
                underlying: error
            )
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(decoding: stderrData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriptionError(
                backend: id.rawValue,
                message:
                    "whisper-cli exited \(process.terminationStatus)"
                    + (stderrText.isEmpty ? "" : ": \(stderrText.suffix(300))")
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
