## ADDED Requirements

### Requirement: Honest availability via dedicated venv

The mlx-audio backend SHALL report available only when the dedicated virtual environment python can import `mlx_audio`; when unavailable, transcription attempts SHALL fail with a typed error containing the exact setup commands (uv venv creation + pip install).

#### Scenario: venv missing

- **GIVEN** `~/.bestasr/mlx-env` does not exist
- **WHEN** availability is queried
- **THEN** the backend reports unavailable, and a transcription attempt fails with guidance containing `uv venv` and `mlx-audio`

### Requirement: Persistent JSON-lines worker per model

The engine SHALL run one persistent worker process per model (spawned with the venv python), sending one JSON request per line on stdin and reading one JSON response per line on stdout; the worker SHALL emit a ready line after model load, and per-request errors SHALL be returned as response rows without terminating the worker.

#### Scenario: model load excluded from timed transcription

- **WHEN** two transcriptions for the same model run in sequence
- **THEN** the worker is spawned once, the model loads once (before ready), and the second request reuses the running worker

##### Example: request/response rows

| direction | line |
|---|---|
| → | `{"id":1,"audio":"/tmp/clip.wav","language":"en"}` |
| ← | `{"id":1,"text":"hello world","segments":[{"start":0.0,"end":2.5,"text":"hello world"}],"language":"en","error":null}` |

### Requirement: Worker lifecycle follows the keep-current cache

Workers SHALL be cached with create-once semantics keyed by model and evicted with keep-current semantics: switching models terminates the previous worker process before the new model's worker is created.

#### Scenario: switching models kills the old worker

- **GIVEN** a running worker for model A
- **WHEN** a transcription for model B starts
- **THEN** worker A's process is terminated and only worker B remains resident

### Requirement: Output normalization and prompt honesty

Worker responses SHALL be mapped to the shared raw-transcription shape (segments with start/end/text; whole-text fallback as a single segment when segments are absent). The context prompt SHALL be ignored by this backend in v1 and the explain output SHALL disclose that biasing is unsupported here.

#### Scenario: segments absent

- **WHEN** a response carries text but no segments
- **THEN** the transcript contains one segment spanning 0..duration with the full text
