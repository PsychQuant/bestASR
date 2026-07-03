## REMOVED Requirements

### Requirement: Honest availability via dedicated venv

**Reason**: mlx-audio backend removed per user decision (#20) — integration cost exceeded need; model catalog retained as reference only.

### Requirement: Persistent JSON-lines worker per model

**Reason**: backend removed (#20); no worker process remains.

### Requirement: Worker lifecycle follows the keep-current cache

**Reason**: backend removed (#20).

### Requirement: Output normalization and prompt honesty

**Reason**: backend removed (#20); prompt-honesty disclosure exits with it.
