import ArgumentParser
import BestASRCLICore
import BestASRKit
import Foundation

// A hermetic host for the two things about `transcribe` that can only be
// observed by running a process (#136).
//
// **Mode `transcribe`** runs the real `Transcribe` command — real parsing, real
// `runMapped`, real call to `TranscribeDiagnostics.report` — against an injected
// `CommandCore` that has a stub engine and a stub language detector. Nothing is
// downloaded and `$HOME` is never read. The test spawns this and reads fd 1 and
// fd 2 separately, so a guard around the reporting call, a rebuilt payload, an
// overridden stream, a hardcoded `explain:`, a deleted call, or a `--explain`
// flag that no longer exists all show up the same way: as bytes that are not
// where they should be.
//
// Four rounds of #136 asserted those properties by reading the command's source
// as text, and each round the pin was shown through on an axis nobody had
// thought to encode. This mode has to be told nothing.
//
// **Mode `report`** (the original) calls `TranscribeDiagnostics.report` passing
// **no streams**, so the test observes the declaration's defaults. That is a
// different property from the one above — mode `transcribe` shows where the
// bytes go given whatever the call site does, mode `report` shows what the
// defaults are given no call site at all — and both are needed, because the
// call site is allowed to be exactly `report(result, explain: explain)`.
//
// Not a package product: `release-app.sh` and `release-mcp.sh` build
// per-product and `install.sh` copies two named binaries, so nothing ships it.

private struct StubEngine: Engine {
    let id: BackendID
    let available: Bool
    func isAvailable() async -> Bool { available }
    func transcribeRaw(audioPath: String, options: TranscribeOptions) async throws
        -> RawTranscription
    {
        // `BESTASR_PROBE_ENGINE_ERROR_FILE` drives the CLI's typed-failure
        // channel, which is the other thing only a running process can show:
        // that `runMapped` still writes through `ConsoleLine`, to fd 2, without
        // truncating. An external adapter's stderr reaches this message verbatim
        // (#51), so the bytes are used as-is — embedded NUL included, which is
        // why this arrives in a FILE rather than in the environment. An
        // environment value cannot carry a NUL: `environ` is an array of
        // NUL-terminated C strings, and `Process` aborts trying to form one.
        if let path = ProcessInfo.processInfo.environment["BESTASR_PROBE_ENGINE_ERROR_FILE"],
            let data = FileManager.default.contents(atPath: path)
        {
            throw TranscriptionError(
                backend: id.rawValue, message: String(decoding: data, as: UTF8.self),
                underlying: nil)
        }
        return RawTranscription(
            segments: [.init(start: 0.0, end: 1.0, text: "hello world")],
            language: "en", duration: 1.0)
    }
}

private struct StubLanguageDetector: AudioLanguageDetecting {
    func detectLanguage(audioPath: String) async throws -> String { "en" }
}

/// A core with no model, no network and no `$HOME` dependence. `whisperkit` is
/// available and nothing else is, which is what makes `--backend fluid-parakeet`
/// produce the substitution warning the default path must surface.
private func stubCore(storeDir: String) -> CommandCore {
    CommandCore(
        engines: [StubEngine(id: .whisperKit, available: true)],
        detect: { SystemInfo(chip: "Apple M5 Max", unifiedMemoryGB: 128, hasANE: true, macosVersion: "26.0") },
        store: BenchmarkStore(directory: URL(fileURLWithPath: storeDir)),
        languageDetector: StubLanguageDetector()
    )
}

private func usage() -> Never {
    ConsoleLine.write(
        """
        usage: bestasr-diagnostics-probe transcribe <storeDir> -- <bestasr transcribe argv…>
               bestasr-diagnostics-probe report <0|1 explain> <outputPath> <format> \
        <explanation> [warning…]

        """, to: stderr)
    exit(64)
}

let argv = Array(CommandLine.arguments.dropFirst())
guard let mode = argv.first else { usage() }

switch mode {
case "transcribe":
    // argv: transcribe <storeDir> -- <command argv…>
    guard argv.count >= 4, argv[2] == "--" else { usage() }
    let commandArgs = Array(argv.dropFirst(3))
    let core = stubCore(storeDir: argv[1])
    do {
        // Parse and run exactly as the executable does. `parse` throwing is a
        // real signal: it is what a removed `--explain` flag looks like.
        var command = try Transcribe.parse(commandArgs)
        try await CommandCore.$injected.withValue(core) {
            try await command.run()
        }
    } catch let code as ExitCode {
        if code.rawValue != 0 { exit(code.rawValue) }
    } catch {
        // Includes ArgumentParser's usage errors. Written to fd 2 in the shape
        // the CLI itself would use, then a distinct exit code so a test can tell
        // "the command refused the arguments" from "the command ran and printed
        // the wrong thing".
        ConsoleLine.write("probe: \(Transcribe.message(for: error))\n", to: stderr)
        exit(65)
    }

case "report":
    let args = Array(argv.dropFirst())
    guard args.count >= 4, let explainFlag = Int(args[0]), explainFlag == 0 || explainFlag == 1
    else { usage() }
    let outcome = TranscribeOutcome(
        outputPath: args[1], format: args[2], explanation: args[3],
        warnings: Array(args.dropFirst(4)))
    // No stream arguments. That is the whole point of this mode: the call reads
    // the same two defaults the CLI reads, so a test spawning this process with
    // separate pipes on fd 1 and fd 2 observes them. Passing streams here would
    // test the arguments and leave the defaults unexamined.
    TranscribeDiagnostics.report(outcome, explain: explainFlag == 1)

default:
    usage()
}
