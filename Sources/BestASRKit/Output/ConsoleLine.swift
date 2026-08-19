import Foundation

/// Writing a line to a console stream, for channels that must survive both a
/// hostile string and a hostile file descriptor (#136).
///
/// Two failure modes have to be avoided at once, and the two obvious APIs each
/// avoid only one:
///
/// - `FileHandle.write(_:)` preserves embedded NUL, but raises an *uncatchable*
///   Objective-C exception when the write fails — so `2>&-` turned a successful
///   run into SIGABRT (exit 134) and `2> >(head -n1)` into SIGPIPE (141), with
///   the transcript already on disk.
/// - `fputs` cannot trap, but takes a NUL-terminated C string: an embedded
///   U+0000 truncates the line *and* swallows its terminator, gluing the next
///   line onto the remains of this one.
///
/// `fwrite` over the UTF-8 bytes avoids both. This is not hypothetical on either
/// channel: an external adapter's stderr is embedded verbatim into
/// `TranscriptionError.message` (`ExternalProcessEngine`), and adapters are
/// third-party programs registered from `~/.bestasr/engines.json` (#51). An
/// adapter emitting `printf 'boom\0DETAIL' >&2` truncated the reported error and
/// glued the following one to it, measured end-to-end.
///
/// Scope, because the narrative above reads wider than it is: this covers the
/// two channels `transcribe` reports through — router diagnostics and the CLI's
/// typed failures. Five other sites in this package still call
/// `FileHandle.standardError.write(_:)` and still abort under `2>&-`, one of
/// them (`ExternalProcessEngine`'s registry warning) on every `transcribe` run.
/// Converting them is a separate change with its own risk; what is fixed here
/// is the channel #136 promoted to the default path, not the class.
///
/// The write and the flush results are both ignored, on purpose: these are
/// reporting channels, and a lost line beats a dead process holding a finished
/// transcript. The honest cost is that under `2>&-` a run now discards its
/// diagnostics and exits 0 where it used to abort, so a caller gating on `$?`
/// with a closed fd 2 gets a transcript whose warning was destroyed without
/// trace. Note also what this does *not* buy: SIGPIPE can still kill the process
/// during `fwrite` or `fflush`, before there is any return value to ignore.
/// Short writes are likewise not retried — a full or quota'd filesystem can
/// truncate a line so that it still reads as complete.
public enum ConsoleLine {

    /// Writes `text` verbatim as UTF-8 bytes, then flushes.
    ///
    /// `text` is written exactly as given; callers that want a line break
    /// include it. Nothing is appended, so a caller can compose a line from
    /// several calls without this deciding where it ends.
    public static func write(_ text: String, to stream: UnsafeMutablePointer<FILE>) {
        var bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return }
        _ = fwrite(&bytes, 1, bytes.count, stream)
        fflush(stream)
    }
}
