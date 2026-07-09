## Why

The bestASR MCP `transcribe` tool is synchronous — the whole MCP call blocks until transcription finishes. For long audio the client can hit its request timeout, and the consuming agent cannot proceed. Because MCP is consumed by AI agents (not humans), the design must optimize for agent behavior: agents discover tools from the tool list + schemas (not out-of-band conventions), need typed error signals to recover, and burn context on busy poll-loops. An opt-in async job mode lets long transcriptions run without tripping timeouts, while keeping the synchronous path as the default — which is the best experience for an agent when the audio fits within the timeout (one call, no polling, no job bookkeeping).

## What Changes

- `transcribe` gains an optional `async` boolean argument (default `false` → current synchronous behavior, zero breakage for existing MCP clients).
- When `async` is `true`, `transcribe` starts the transcription on a background task routed through the existing single-flight gate (preserving the single-model-resident invariant from the mcp-surface change), and returns immediately with a `job_id` and status `running`.
- New tool `transcribe_status` — given a `job_id`, returns `running` / `done` / `failed`, with a typed error message on failure.
- New tool `transcribe_result` — given a `job_id`, performs a bounded server-side long-poll: it waits until the job completes or a cap elapses, then returns the transcript, `still_running`, or the typed error. This lets an agent make one result call instead of a busy poll-loop.
- Jobs are tracked by an in-memory job registry keyed by `job_id` (state plus result payload) with time-based cleanup so completed jobs do not grow memory unbounded in a long-lived server.

## Non-Goals

- Persistent job storage across server restarts. The registry is in-memory only; a server restart loses in-flight and completed job state. Documented as a v1 limitation.
- Cancellation of an in-flight job.
- Progress percentage or partial-transcript streaming. Status is coarse: `running` / `done` / `failed`.
- Any change to the synchronous default or to the current behavior of existing tools. Callers that do not pass `async: true` observe no difference.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `mcp-surface`: adds an opt-in async job mode to the `transcribe` tool and two polling tools (`transcribe_status`, `transcribe_result`) backed by an in-memory job registry.

## Impact

- Affected specs: `mcp-surface` (ADDED requirements for async job mode + status/result tools)
- Affected code:
  - New: Sources/BestASRMCPCore/JobRegistry.swift
  - Modified: Sources/BestASRMCPCore/Server.swift
  - Modified: Tests/BestASRKitTests/MCPServerTests.swift
