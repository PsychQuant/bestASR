## 1. JobRegistry actor — Requirement: Async job registry is bounded and non-persistent


- [x] 1.1 Add a failing test that drives a `JobRegistry` with an injected async work closure (no real engine): `start(work:)` returns a job id, `status` transitions running→done, and `awaitResult` returns the payload for a completing job. Verification: new test in the MCP test target fails before implementation, passes after.
- [x] 1.2 Implement the `JobRegistry` actor in Sources/BestASRMCPCore/JobRegistry.swift — UUID job_id keying, a JobState enum (running/done/failed), a result payload holding the rendered transcript text + explanation or a typed error string, plus `start(work:)`, `status(jobId)`, and `awaitResult(jobId, cap)` where the bounded wait returns done / still_running / failed. Verification: task 1.1 test passes.
- [x] 1.3 Add time-based eviction so a completed job is fetchable, then evicted after a retention window; a fetch after eviction reports unknown-job. Verification: an eviction test with a short retention window asserts fetchable-then-unknown-job.
- [x] 1.4 Failing-job path: an injected throwing work closure transitions the job to failed carrying the typed message; `status` returns failed and `awaitResult` returns the typed error. Verification: a failure test asserts the failed state and the error message.

## 2. Async transcribe dispatch — Requirement: Transcribe supports an opt-in async job mode


- [x] 2.1 Add a failing test asserting `transcribe` with `async` true returns a job id and status running without blocking for the transcription duration. Verification: the async-returns-job-id test fails before the dispatch branch exists, passes after.
- [x] 2.2 Add the `async` boolean property (default false) to the transcribe tool schema and branch the dispatch transcribe case: `async` false/absent keeps the existing synchronous path byte-for-byte; `async` true starts the transcription inside `transcribeGate.run` on a background task registered with the `JobRegistry`, returning the job id and status running. Verification: task 2.1 passes and every existing synchronous transcribe test stays green.
- [x] 2.3 Confirm async transcribes remain serialized: the background transcription work runs inside `transcribeGate.run` so at most one transcription hits the engine at a time. Verification: the existing SingleFlight serialization test stays green and the async dispatch path routes through the gate.

## 3. Status and result tools — Requirement: Async job status and result tools


- [x] 3.1 Add failing tests for the two poll tools: `transcribe_status` returns running then done across a job's lifecycle; `transcribe_result` long-polls to the transcript within the cap; `transcribe_result` returns still_running when the cap is hit on a slow job; an unknown job id is a loud tool error on both tools. Verification: the new tool tests fail before the dispatch cases exist, pass after.
- [x] 3.2 Define `transcribe_status` and `transcribe_result` Tool schemas (each requires a `job_id` string, annotated read-only) and add dispatch cases delegating to `JobRegistry.status` / `awaitResult`; an unknown job id raises a loud `BestASRError`. Verification: task 3.1 passes.

## 4. Tool surface and docs — Requirement: Async tools extend the stdio tool surface


- [x] 4.1 Update the tool-list test to assert exactly the seven tools (transcribe, recommend, list_backends, list_models, corpus_add, transcribe_status, transcribe_result) and that the two new tools carry the read-only hint. Verification: the updated tool-list test passes.
- [x] 4.2 [P] Update the README MCP section to note that `transcribe` accepts an `async` flag and that `transcribe_status` / `transcribe_result` exist for polling long jobs (agent long-audio usage). Verification: the README diff shows the async + poll-tools note; content review.

## 5. Verification

- [x] 5.1 The full `swift test` suite passes. Verification: `swift test` exits 0 with no failures.
- [x] 5.2 Live stdio round-trip on the debug binary (stdin held open): tools/list shows the seven tools and an `async` transcribe returns a job id with status running. Verification: the round-trip output shows seven tools and a running job id.
