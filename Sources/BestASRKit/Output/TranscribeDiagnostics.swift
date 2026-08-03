import Foundation

/// What a `transcribe` run tells the reader besides the transcript path, and
/// where it goes (#136).
///
/// This lives in the library rather than in `Sources/bestasr/` for one reason:
/// the executable target has no test coverage at all, and #136's third
/// acceptance line asks for *"a test [that] asserts the warning reaches stderr
/// on the default path — the current suite would not have caught this."* The
/// first fix satisfied that at the data layer (`TranscribeOutcome.warnings` is
/// populated) and left the layer the bug actually lived in untested: deleting
/// the CLI's entire printing branch kept the whole suite green, which is the
/// same failure mode one level up.
///
/// The split below is deliberate. `lines(for:explain:)` is pure, so the branch
/// and the prefix are cheap to assert — but a test of it alone cannot see a
/// regression that sends the same strings to *stdout*, which for anyone piping
/// a transcript is #136 again. `emit(for:explain:)` is therefore the thing the
/// CLI calls, and the destination is asserted by redirecting fd 2 around it.
public enum TranscribeDiagnostics {

    /// The lines a run should surface, in order. Pure: no I/O, no globals.
    ///
    /// `--explain` renders the explanation block, which already contains the
    /// warnings inline and in context with the reasons; printing them again
    /// would duplicate. The default path renders the warnings alone, prefixed.
    /// The two are mutually exclusive by construction rather than by content
    /// comparison, so duplication is not merely absent, it is unrepresentable.
    public static func lines(for outcome: TranscribeOutcome, explain: Bool) -> [String] {
        if explain {
            return outcome.explanation.isEmpty ? [] : [outcome.explanation]
        }
        return outcome.warnings.map { "warning: \($0)" }
    }

    /// Where diagnostics go.
    ///
    /// Named rather than inlined so a test can assert it — the destination is
    /// precisely the half that a pure test of `lines(for:explain:)` cannot see,
    /// and a one-word change to `stdout` would reintroduce #136 for anyone
    /// piping a transcript while every string-level assertion stayed green.
    ///
    /// The alternative — redirecting the process's real fd 2 around a call —
    /// tests the same property more directly and must not be used *here*:
    /// inside a test bundle, `close(2)` hands fd 2 to whatever the harness opens
    /// next, and restoring it then closes that resource out from under the
    /// harness. Correct technique, wrong host.
    public static let destination: UnsafeMutablePointer<FILE> = stderr

    /// Writes those lines to `stream`.
    ///
    /// `fputs` rather than `FileHandle.standardError.write(_:)`: the latter
    /// raises an *uncatchable* Objective-C exception when the write fails, so a
    /// closed fd 2 (`2>&-`) or a stderr reader that exits early
    /// (`2> >(head -n1)`) turned a **successful** transcription into SIGABRT or
    /// SIGPIPE — transcript already on disk, `Wrote …` already printed, exit
    /// code 134 or 141. The misuse predates #136, but #136 promoted it from
    /// `--explain`-only to the default path, and this repo ships skill
    /// templates that gate on `$?`. An exit code that stops describing what
    /// happened is the same defect this issue is named after, one layer out.
    public static func emit(
        for outcome: TranscribeOutcome, explain: Bool,
        to stream: UnsafeMutablePointer<FILE> = destination
    ) {
        for line in lines(for: outcome, explain: explain) {
            fputs(line + "\n", stream)
        }
        fflush(stream)
    }
}
