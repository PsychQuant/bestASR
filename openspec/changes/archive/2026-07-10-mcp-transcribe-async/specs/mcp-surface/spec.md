## ADDED Requirements

### Requirement: Transcribe supports an opt-in async job mode

The `transcribe` tool SHALL accept an optional `async` boolean argument that defaults to false. When `async` is false or absent, `transcribe` SHALL behave synchronously and return the transcript inline (existing behavior preserved). When `async` is true, `transcribe` SHALL start the transcription on a background task routed through the same single-flight serialization that guards synchronous transcribes (so at most one transcription runs against the single-model engine at a time), and SHALL return immediately with a job identifier and a status of `running`.

#### Scenario: Synchronous default is unchanged

- **WHEN** transcribe is called without `async` (or with `async` false)
- **THEN** it returns the transcript inline exactly as before, blocking until done

#### Scenario: Async returns a job id immediately

- **WHEN** transcribe is called with `async` true
- **THEN** it returns immediately with a job_id and status running, without blocking for the transcription duration

#### Scenario: Async transcribes remain serialized

- **WHEN** two async transcribes for distinct models are started concurrently
- **THEN** they do not run against the engine at the same time (the single-flight invariant is preserved)

### Requirement: Async job status and result tools

The system SHALL provide two tools for async jobs. `transcribe_status` SHALL, given a job_id, return the job state as `running`, `done`, or `failed` (carrying a typed error message when failed). `transcribe_result` SHALL, given a job_id, perform a bounded server-side wait up to a fixed cap and then return the completed transcript, an indication that the job is `still_running`, or the typed error if the job failed. An unknown job_id SHALL be a loud tool error for both tools.

#### Scenario: Status reports running then done

- **WHEN** transcribe_status is queried for a job that is still running
- **THEN** it returns running
- **WHEN** transcribe_status is queried after the job has completed
- **THEN** it returns done

#### Scenario: Result long-polls to completion in one call

- **WHEN** transcribe_result is called for a job that completes within the wait cap
- **THEN** it blocks until completion and returns the transcript in that single call

#### Scenario: Result caps the wait rather than blocking forever

- **WHEN** transcribe_result is called for a job that does not complete within the wait cap
- **THEN** it returns still_running so the caller may call again, rather than blocking indefinitely

#### Scenario: Failed job surfaces the typed error

- **WHEN** a job has failed
- **THEN** transcribe_status returns failed and transcribe_result returns the typed error message

#### Scenario: Unknown job id is a loud error

- **WHEN** transcribe_status or transcribe_result is given a job_id that does not exist
- **THEN** the reply is a loud tool error naming the unknown job

### Requirement: Async job registry is bounded and non-persistent

Completed async jobs SHALL be retained in an in-memory registry long enough to be fetched, then evicted by a time-based cleanup so that a long-lived server does not accumulate job state without bound. In-memory job state SHALL NOT survive a server restart; this limitation SHALL be documented in the design record.

#### Scenario: Completed job is fetchable then evicted

- **WHEN** an async job completes
- **THEN** its result is fetchable via transcribe_result
- **WHEN** the retention window has elapsed after completion
- **THEN** the job is evicted and a subsequent fetch is a loud unknown-job error

#### Scenario: Restart loses tracked jobs

- **WHEN** the server process restarts
- **THEN** previously tracked job ids are no longer known (documented v1 limitation)

### Requirement: Async tools extend the stdio tool surface

When the async job mode ships, the stdio tool list SHALL include `transcribe_status` and `transcribe_result` in addition to the existing tools, and the read-only-hint annotations SHALL mark both new tools read-only.

#### Scenario: Async tools appear in the tool list

- **WHEN** an MCP client requests the tool list
- **THEN** transcribe_status and transcribe_result are present alongside transcribe, recommend, list_backends, list_models, and corpus_add
