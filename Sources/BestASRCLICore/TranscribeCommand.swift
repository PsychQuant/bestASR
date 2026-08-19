import ArgumentParser
import BestASRKit
import Foundation

/// The `transcribe` command, in a library target so a test can **run** it.
///
/// Everything here used to live in the `bestasr` executable, where the only way
/// to assert its wiring was to read the file as text. Four rounds of #136 did
/// exactly that, and each round the pin was shown through on an axis it had not
/// been told about — the guard's spelling, then the stream labels, then the
/// payload argument, then whether `--explain` still existed as a flag. A test
/// that runs the command needs to be told none of them: it looks at the file
/// descriptors and sees whatever actually happened.
///
/// Only `transcribe` moved. The other nine commands stay in the executable,
/// because #136 is about this one and a wider move would be a refactor wearing
/// a bug fix's clothes. `runMapped` and `SelectionOptions` came along because
/// `Transcribe` cannot compile without them; both are still used by the
/// commands that stayed.
///
/// This target is deliberately **not** a package product, so making these types
/// `public` exposes them to the rest of this package and to nothing outside it.

// The library enum is ArgumentParser-free (BestASRKit has no such dependency);
// the CLI adds the conformance here. RawValue is String, so ArgumentParser
// derives `init?(argument:)` and lists the cases (off | denylist) in --help.
// (Same package as the enum, so no @retroactive.) It lives beside `Transcribe`
// because that is the only command with the option; `RunKind`'s equivalent
// stayed with `benchmark` in the executable.
extension HallucinationFilterMode: ExpressibleByArgument {}

/// Maps the two typed failures onto exit codes, and writes the one line the
/// user sees when a run fails.
public func runMapped(_ body: () async throws -> Void) async throws {
    do {
        try await body()
    } catch let error as BestASRError {
        // Same writer as the diagnostics channel. An intermediate version of
        // this fix used `fputs` here — which stops the SIGABRT but truncates at
        // an embedded NUL, and this is the channel where a NUL is *reachable*:
        // an external adapter's stderr goes verbatim into
        // `TranscriptionError.message`, and adapters are third-party programs
        // (#51). See `ConsoleLine`.
        ConsoleLine.write("error: \(error.errorDescription ?? "failed")\n", to: stderr)
        throw ExitCode(error.exitCode)
    } catch let error as TranscriptionError {
        ConsoleLine.write(
            "error: \(error.errorDescription ?? "transcription failed")\n", to: stderr)
        throw ExitCode(1)
    }
}

public struct SelectionOptions: ParsableArguments {
    @Option(
        help:
            "Effort profile: auto | low | medium | high | xhigh | max — auto adapts to machine pressure; max = most accurate regardless of time"
    )
    var profile: String = "auto"

    @Option(
        help: ArgumentHelp(
            "Force a backend: auto | "
                + BackendID.allCases.map(\.rawValue).joined(separator: " | ")))
    var backend: String = "auto"

    @Option(
        help: "Force a model size: auto | \(ModelRegistry.supportedModels.joined(separator: " | ")) | 0.6b-v3 (fluid-parakeet)")
    var model: String = "auto"

    @Option(help: "Audio language code, or 'auto'")
    var language: String = "auto"

    @Option(
        help: "Context documents directory for context biasing (top-down / prompt biasing: bias decoding toward your domain vocabulary, names, and terms; default: three-layer resolution)"
    )
    var contextDir: String?

    public init() {}

    public func resolved() -> SelectionRequest {
        SelectionRequest(
            profileName: profile,
            backendOverride: backend == "auto" ? nil : backend,
            modelOverride: model == "auto" ? nil : model,
            requestedLanguage: language,
            contextDir: contextDir
        )
    }
}

public struct Transcribe: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe an audio file with the best setup for this machine"
    )

    @Argument(help: "Path to the input audio file")
    var audio: String

    @OptionGroup var selection: SelectionOptions

    @Option(help: "Output format: \(OutputFormat.allNames.joined(separator: " | "))")
    var format: String = OutputFormat.txt.rawValue

    @Option(help: "Output file path (default: derived from the input file name)")
    var output: String?

    @Flag(help: "Explain why this backend/model was chosen (printed to stderr)")
    var explain = false

    @Flag(help: "Label each cue with an acoustic speaker (SPEAKER_1…); downloads CoreML diarization models on first use")
    var diarize = false

    @Option(help: "Strip decoder hallucinations before writing: off | denylist | full (confidence-gated, WhisperKit signals; default denylist)")
    var hallucinationFilter: HallucinationFilterMode = .denylist

    @Option(help: "Decode knob (WhisperKit only): mark segments above this no-speech probability as silence (default: WhisperKit's)")
    var noSpeechThreshold: Double?

    @Option(help: "Decode knob (WhisperKit only): treat segments above this compression ratio as failed/repetitive (default: WhisperKit's)")
    var compressionRatioThreshold: Double?

    // parsing: .unconditional — the meaningful domain is all-negative (it's a
    // log-prob floor), and ArgumentParser's default strategy rejects a leading
    // dash ("--logprob-threshold -1.0" → 'Missing value'). Unconditional
    // consumes the next token as the value (verify #101 HIGH).
    @Option(
        parsing: .unconditional,
        help:
            "Decode knob (WhisperKit only): average-logprob floor below which a segment decode is retried/marked (negative, e.g. -1.0; default: WhisperKit's). Note: with --decode-deterministic, threshold trips mark/skip segments instead of triggering a fallback retry"
    )
    var logprobThreshold: Double?

    public init() {}

    public func run() async throws {
        try await runMapped {
            let result = try await CommandCore.live().transcribe(
                audioPath: audio,
                selection: selection.resolved(),
                formatName: format,
                outputPath: output,
                diarize: diarize,
                hallucinationFilter: hallucinationFilter,
                noSpeechThreshold: noSpeechThreshold,
                compressionRatioThreshold: compressionRatioThreshold,
                logProbThreshold: logprobThreshold
            )
            // #136: warnings print on the DEFAULT path. Reasons explain a
            // choice and are opt-in; a warning is what the reader needs to trust
            // the file just written. Hiding these behind --explain meant
            // `--backend X` could silently deliver backend Y's output with
            // "Wrote txt transcript to …" as the entire output.
            //
            // Emitted BEFORE the success line, as a presentation choice, not a
            // buffering necessity: `report` flushes both streams, so under
            // `2>&1` the observed order is simply the call order — measured
            // stable in both directions on a pty, a pipe and a file. The reverse
            // reads oddly (the file announced as written before the reason to
            // distrust it), and across two separate pipes nothing is guaranteed
            // either way.
            //
            // No source-text pin guards this line any more. `TranscribeWiring…`
            // in the test target runs this command in a subprocess and reads the
            // descriptors, so a guard, a rebuilt payload, an overridden stream,
            // a hardcoded `explain:`, or a deleted call all show up as the
            // absence of bytes rather than as the absence of a string.
            TranscribeDiagnostics.report(result, explain: explain)
        }
    }
}
