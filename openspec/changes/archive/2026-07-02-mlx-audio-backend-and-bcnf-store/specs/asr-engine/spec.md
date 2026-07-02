## MODIFIED Requirements

### Requirement: Availability detection is graceful

`is_available()` SHALL determine whether the underlying package and runtime are usable by probing via lazy import or an equivalent runtime probe, and SHALL return false rather than raising when the package or runtime is absent. For the mlx-audio backend the probe SHALL verify that the dedicated virtual environment's python can import `mlx_audio`.

#### Scenario: Uninstalled backend reports unavailable

- **WHEN** `is_available()` is called for a backend whose underlying package is not installed
- **THEN** it returns false
- **AND** no ImportError propagates to the caller

#### Scenario: mlx-audio venv probe

- **GIVEN** the dedicated venv is absent or cannot import `mlx_audio`
- **WHEN** availability is queried for the mlx-audio backend
- **THEN** it returns false without raising
