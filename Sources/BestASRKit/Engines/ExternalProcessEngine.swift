import Foundation

/// External-process engine (#51, spec external-engine-protocol): any
/// executable speaking the versioned JSON protocol can join the competition
/// pool. This is the containment answer to #20 — the adapter owns its own
/// runtime (venv, model cache, upstream churn); bestASR spawns one process
/// per transcription over an argv array (never a shell), enforces a timeout,
/// and consumes exactly one JSON object from stdout.
///
/// Protocol v1 (design D1):
///
///   <command...> transcribe --audio <path> --model <model>
///                [--language <code>] [--hf-repo <repo>] [--revision <rev>]
///
///   stdout on success: {"protocol":1, "text":"...", "duration":12.3,
///                       "segments":[{"start","end","text"}]? }
///   failure: non-zero exit, message on stderr → typed TranscriptionError.
public struct ExternalProcessEngine: Engine {
    /// Protocol versions this host understands.
    static let supportedProtocols: Set<Int> = [1]

    public let id: BackendID
    let command: [String]
    /// Test seam — production timeout is `max(120s, 4x audio duration)` (D3);
    /// duration is unknown before probing, so the floor applies to short files.
    let timeoutOverride: TimeInterval?

    public init(id: BackendID, command: [String], timeoutOverride: TimeInterval? = nil) {
        self.id = id
        self.command = command
        self.timeoutOverride = timeoutOverride
    }

    public func isAvailable() async -> Bool {
        guard let executable = command.first else { return false }
        return FileManager.default.isExecutableFile(atPath: executable)
    }

    struct ProtocolReply: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
        }
        let `protocol`: Int
        let text: String
        let duration: Double
        let segments: [Segment]?
    }

    public func transcribeRaw(
        audioPath: String, options: TranscribeOptions
    ) async throws -> RawTranscription {
        var arguments = Array(command.dropFirst())
        arguments += ["transcribe", "--audio", audioPath, "--model", options.model]
        if let language = options.language {
            arguments += ["--language", language]
        }
        let row = ModelGrid.row(backend: id.rawValue, modelAddress: options.model)
        if let repo = row?.hfRepo {
            arguments += ["--hf-repo", repo]
        }
        if let revision = row?.hfRevision {
            arguments += ["--revision", revision]
        }

        let probed = (try? AudioProber.probe(path: audioPath, requestedLanguage: nil).duration) ?? nil
        let timeout = timeoutOverride ?? max(120, (probed ?? 0) * 4)

        let (status, stdout, stderr) = try await Self.run(
            executable: command[0], arguments: arguments, timeout: timeout, backend: id.rawValue)

        guard status == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriptionError(
                backend: id.rawValue,
                message: "adapter exited \(status): \(message.isEmpty ? "(no stderr)" : message)",
                underlying: nil)
        }

        let reply: ProtocolReply
        do {
            reply = try JSONDecoder().decode(ProtocolReply.self, from: Data(stdout.utf8))
        } catch {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "adapter stdout is not a protocol JSON object: "
                    + "\(stdout.prefix(200))",
                underlying: error)
        }
        guard Self.supportedProtocols.contains(reply.protocol) else {
            throw TranscriptionError(
                backend: id.rawValue,
                message: "unsupported adapter protocol version \(reply.protocol) "
                    + "(host supports \(Self.supportedProtocols.sorted()))",
                underlying: nil)
        }

        return RawTranscription(
            segments: Self.segments(from: reply),
            language: options.language,
            duration: reply.duration)
    }

    /// Timed segments flow through when the whole batch is trustworthy;
    /// one inverted pair distrusts the batch and the FULL reply text becomes
    /// a single segment instead (#53 batch-distrust semantics — dropping a
    /// timed segment would drop its text, and the transcript text is joined
    /// from segments, so partial drops silently corrupt WER). Empty-text
    /// entries are skipped (no text to lose).
    static func segments(from reply: ProtocolReply) -> [RawTranscription.RawSegment] {
        let upper = max(reply.duration, 0)
        func fullText() -> [RawTranscription.RawSegment] {
            let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return [] }
            return [.init(start: 0, end: upper, text: text, confidence: nil)]
        }
        guard let timed = reply.segments, !timed.isEmpty else { return fullText() }
        var sane: [RawTranscription.RawSegment] = []
        for s in timed {
            guard s.end >= s.start else { return fullText() }  // batch distrusted
            guard !s.text.isEmpty else { continue }
            let start = min(max(s.start, 0), upper)
            let end = min(max(s.end, 0), upper)
            if end == start && s.end > s.start { return fullText() }  // entirely out of range
            sane.append(.init(start: start, end: end, text: s.text, confidence: nil))
        }
        return sane.isEmpty ? fullText() : sane
    }

    /// Spawn + collect with a hard timeout (D3).
    ///
    /// The concurrent-drain + deadline machinery this used to own now lives in
    /// `SubprocessRunner`, so `WhisperCppEngine` and every future engine get it
    /// too — #165 was the same bug as #91, surviving only because the fix
    /// stayed local to this file. Kept as a thin alias so existing call sites
    /// and their `adapter`-flavoured error text read unchanged.
    static func run(
        executable: String, arguments: [String], timeout: TimeInterval, backend: String
    ) async throws -> (Int32, String, String) {
        try await SubprocessRunner.run(
            executable: executable, arguments: arguments, timeout: timeout, backend: backend)
    }
}

/// Registry of user-configured external engines (#51 design D6):
/// `~/.bestasr/engines.json`. Unknown ids warn and drop (hand-written
/// config, fail-soft); a missing file means no external backends at all.
public struct ExternalEngineRegistry {
    public struct Entry {
        public let id: BackendID
        public let command: [String]
    }

    public let engines: [Entry]

    public static var defaultConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".bestasr/engines.json")
    }

    public init(configPath: String = ExternalEngineRegistry.defaultConfigPath) {
        struct Config: Decodable {
            struct RawEntry: Decodable {
                let id: String
                let command: [String]
            }
            let engines: [RawEntry]
        }
        guard let data = FileManager.default.contents(atPath: configPath),
            let config = try? JSONDecoder().decode(Config.self, from: data)
        else {
            self.engines = []
            return
        }
        self.engines = config.engines.compactMap { raw in
            guard let id = BackendID(rawValue: raw.id), Self.externalCapable.contains(id),
                !raw.command.isEmpty
            else {
                FileHandle.standardError.write(Data(
                    "warning: engines.json entry '\(raw.id)' is not an external-capable backend — ignored\n"
                        .utf8))
                return nil
            }
            return Entry(id: id, command: raw.command)
        }
    }

    /// Backends that may be driven by an external adapter (D2: one enum case
    /// per tool keeps BackendID closed and type-safe).
    static let externalCapable: Set<BackendID> = [.mlxAudio]
}
