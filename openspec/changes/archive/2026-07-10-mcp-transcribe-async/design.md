## Context

The bestASR MCP surface (mcp-surface change, #80) exposes a synchronous `transcribe` tool: `BestASRMCPServer.dispatch` awaits `core.transcribe` to completion, serialized by a `SingleFlight` gate so concurrent transcribes cannot overlap the single-model engine. The whole MCP call blocks for the transcription duration, which can exceed an MCP client's request timeout on long audio.

The consumer of this surface is an AI agent, not a human. That shapes the design: agents discover tools from the tool list plus schemas (out-of-band file conventions are error-prone for them), agents need typed error signals to recover, and agents burn context on busy poll-loops (each poll is a full model round-trip). Therefore the synchronous path is the best experience when the audio fits within the timeout (one call, no polling), and async is an escape hatch for the long tail.

## Goals / Non-Goals

**Goals:**

- Let a caller opt into non-blocking transcription so long jobs do not trip the client timeout.
- Keep the synchronous path the default and byte-for-byte unchanged for existing callers.
- Give agents a self-describing, typed contract: real tools (not file conventions) with typed errors.
- Minimize agent poll-loop cost via a bounded server-side long-poll on the result.
- Preserve the single-model-resident engine invariant for async jobs.
- Bound registry memory so a long-lived server does not leak completed jobs.

**Non-Goals:**

- Persistent job storage across server restarts (in-memory only).
- Job cancellation.
- Progress percentage or partial-transcript streaming (coarse running/done/failed status only).
- Changing any existing tool's current behavior.

## Decisions

**D1 — Opt-in `async` param, sync default.** `transcribe` gains `async: bool` defaulting false. Rationale: zero breakage; sync is the best agent experience when the job fits the timeout; async is a per-call escape hatch chosen by the caller who knows the file is long.

**D2 — Two new tools, not file-return.** `transcribe_status` and `transcribe_result` are first-class MCP tools with schemas. Rationale: agents discover tools from the tool list; a status tool gives an unambiguous state and a typed failure channel; file-existence polling cannot distinguish "not done yet" from "failed" and has no error channel.

**D3 — Bounded server-side long-poll on `transcribe_result`.** Rather than the agent busy-polling `transcribe_status`, `transcribe_result` waits server-side up to a fixed cap and returns the transcript, `still_running`, or the typed error. Rationale: an agent burns context per poll; a single blocking-until-ready result call is cheaper. The cap prevents the result call from itself becoming an unbounded blocking call (the original timeout hazard). `transcribe_status` remains available for a cheap non-blocking state check.

**D4 — In-memory `JobRegistry` actor with TTL eviction.** Jobs are keyed by a UUID `job_id`; each entry holds a state (running/done/failed), the result payload (transcript text + explanation, or a typed error), and a completion timestamp. A completed job is evicted after a retention window so a long-lived server does not accumulate job state (the temp-leak lesson from #43 and mcp-surface F3). Rationale: transcripts are already reproducible and small enough to hold briefly; persistence is out of scope for v1.

**D5 — Async work still routes through `SingleFlight`.** The background task calls `core.transcribe` inside the existing `transcribeGate.run { ... }`, so at most one transcription (sync or async) runs against the engine at a time. Rationale: the single-model-resident invariant (mcp-surface F1/F2) must hold regardless of call shape.

**D6 — Tool-surface evolution.** The tool list grows from five to seven; the two new tools are annotated read-only (they observe job state, they do not start work). The mcp-surface "exactly five v1 tools" scenario from #80 is superseded to seven by the "Async tools extend the stdio tool surface" requirement in this change; the MCPServerTests tool-list assertion is updated from five to seven. Reconciliation of the two changes' tool-count wording happens when both are archived.

## Implementation Contract

**Behavior:**

- `transcribe` with `async` absent/false → unchanged: blocks, returns transcript inline.
- `transcribe` with `async: true` → returns immediately with `job_id` and status `running`; transcription runs in the background through `SingleFlight`.
- `transcribe_status(job_id)` → `running` / `done` / `failed` (+ typed message on failed).
- `transcribe_result(job_id)` → waits up to the cap, then returns the transcript, `still_running`, or the typed error.
- Unknown `job_id` on either tool → loud tool error (isError true) naming the job.
- Completed job is fetchable, then evicted after the retention window; a fetch after eviction is a loud unknown-job error.

**Interface / data shape:**

- New source file with a `JobRegistry` actor: `start(work:) -> jobId`, `status(jobId) -> JobState`, `awaitResult(jobId, cap) -> JobOutcome`, plus internal TTL sweep. `JobState` is an enum running/done/failed; the result payload carries the rendered transcript text + explanation string (same shape the sync path returns) or a typed error string.
- `transcribe` tool schema gains an `async` boolean property (default false).
- Two new `Tool` definitions (`transcribe_status`, `transcribe_result`), each requiring a `job_id` string, annotated `readOnlyHint: true`.
- `dispatch` gains cases for the two new tool names; the `transcribe` case branches on `async`.

**Failure modes:**

- Background transcription throwing → job transitions to failed with the typed message; `transcribe_status` returns failed, `transcribe_result` returns the typed error (loud).
- Unknown job id → loud tool error, server keeps serving.
- Result wait cap elapsed → `still_running` (not an error); caller retries.

**Acceptance criteria:**

- Unit tests in the MCP test suite assert: tool list is exactly the seven tools (five existing + two new); `async:true` transcribe returns a job id without blocking; status transitions running→done for a completing job; result long-poll returns the transcript for a completing job; result returns still_running when the cap is hit on a slow job; a failed job surfaces failed/typed error; unknown job id is loud on both tools; an evicted job is a loud unknown-job error.
- The `JobRegistry` is exercised with an injected fast/slow/failing work closure (no real engine needed) so the async state machine is tested deterministically.
- Full `swift test` suite stays green.

**Scope boundaries:**

- In scope: Server.swift (schemas + dispatch), a new JobRegistry.swift, MCPServerTests.swift additions, the mcp-surface spec delta, README note that transcribe accepts async + the two poll tools exist.
- Out of scope: persistence, cancellation, progress %, any change to sync behavior or other tools, the GUI .app (#87).

## Risks / Trade-offs

- **Memory retention window tuning:** too short and an agent that waits before fetching loses the result; too long and memory grows. Mitigation: a retention window comfortably longer than a typical fetch latency, plus the sweep; documented as a knob.
- **Result long-poll vs. timeout:** the long-poll cap must be shorter than typical MCP client timeouts so `transcribe_result` itself never trips the timeout it exists to avoid; the caller loops on `still_running` for very long jobs.
- **Restart-mid-job:** in-memory state is lost on restart; a caller holding a stale job_id gets a loud unknown-job error. Documented v1 limitation.
- **Tool-count divergence across two un-archived changes:** #80 says five, this says seven; reconciled at archive time. Low risk (additive, documented).
